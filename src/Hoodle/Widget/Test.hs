-----------------------------------------------------------------------------
-- |
-- Module      : Hoodle.Widget.Test
-- Copyright   : (c) 2013 Ian-Woo Kim
--
-- License     : BSD3
-- Maintainer  : Ian-Woo Kim <ianwookim@gmail.com>
-- Stability   : experimental
-- Portability : GHC
--
-----------------------------------------------------------------------------

module Hoodle.Widget.Test where

-- from other packages
import           Control.Category
import           Control.Lens (view,set,over)
import           Control.Monad.Identity 
import           Control.Monad.State 
import           Data.Time.Clock 
import           Graphics.Rendering.Cairo 
import           Graphics.UI.Gtk hiding (get,set) 
-- import           Graphics.UI.Gtk hiding (get,set)
-- import qualified Graphics.UI.Gtk as Gtk (get)
-- from hoodle-platform 
import           Data.Hoodle.BBox
import           Data.Hoodle.Generic
import           Data.Hoodle.Zipper
import           Graphics.Hoodle.Render.Type
import           Graphics.Hoodle.Render.Util
import           Graphics.Hoodle.Render.Util.HitTest
-- 
import           Hoodle.Accessor
import           Hoodle.Coroutine.Draw
import           Hoodle.Coroutine.Page
import           Hoodle.Coroutine.Scroll
import           Hoodle.Coroutine.Select
import           Hoodle.Device
import           Hoodle.ModelAction.Page 
import           Hoodle.ModelAction.Select
import           Hoodle.Type.Alias
import           Hoodle.Type.Canvas
import           Hoodle.Type.Coroutine
import           Hoodle.Type.Event
import           Hoodle.Type.HoodleState 
import           Hoodle.Type.PageArrangement 
import           Hoodle.Type.Predefined 
import           Hoodle.View.Coordinate
import           Hoodle.View.Draw
-- 
import Prelude hiding ((.),id)


data WidgetMode = Moving | Zooming

widgetCheckPen :: CanvasId -> PointerCoord 
               -> MainCoroutine () 
               -> MainCoroutine ()
widgetCheckPen cid pcoord act = do 
    xst <- get
    let cinfobox = getCanvasInfo cid xst 
    boxAction (f xst) cinfobox 
  where 
    f xst cinfo = do 
      let cvs = view drawArea cinfo
          pnum = (PageNum . view currentPageNum) cinfo 
          arr = view (viewInfo.pageArrangement) cinfo
      geometry <- liftIO $ makeCanvasGeometry pnum arr cvs 
      let oxy@(CvsCoord (x,y)) = (desktop2Canvas geometry . device2Desktop geometry) pcoord
      let owxy@(CvsCoord (x0,y0)) = view (canvasWidgets.testWidgetPosition) cinfo
          obbox = BBox (x0,y0) (x0+100,y0+100) 
          ibbox = BBox (x0+30,y0+30) (x0+70,y0+70)
              
          
      if (isPointInBBox obbox (x,y))  
         then do 
           ctime <- liftIO getCurrentTime 
           let mode = case  isPointInBBox ibbox (x,y) of 
                        True -> Zooming 
                        False -> Moving 
           let hdl = getHoodle xst
           (sfc,sfc2) <- liftIO (canvasImageSurface geometry hdl)
           
           startWidgetAction mode cid geometry (sfc,sfc2) owxy oxy ctime 
           liftIO $ surfaceFinish sfc 
           liftIO $ surfaceFinish sfc2
         else do 
           act 


findZoomXform :: ((Double,Double),(Double,Double),(Double,Double)) 
                 -> (Double,(Double,Double))
findZoomXform ((xo,yo),(x0,y0),(x,y)) = 
    let tx = x - x0 --  if x0 > xo then x - x0 else x0 - x 
        ty = y - y0 -- if y0 > yo then y - y0 else y0 - y
        ztx = 1 + tx / 200
        zty = 1 + ty / 200
        zx | ztx > 2 = 2  
           | ztx < 0.5 = 0.5
           | otherwise = ztx
        zy | zty > 2 = 2  
           | zty < 0.5 = 0.5
           | otherwise = zty                                          
        z | zx >= 1 && zy >= 1 = max zx zy
          | zx < 1 && zy < 1 = min zx zy 
          | otherwise = zx
        xtrans = (1 -z)*xo/z
        ytrans = (1- z)*yo/z 
    in (z,(xtrans,ytrans))

-- | 
startWidgetAction :: WidgetMode 
                     -> CanvasId 
                     -> CanvasGeometry 
                     -> (Surface,Surface)
                     -> CanvasCoordinate -- ^ original widget position
                     -> CanvasCoordinate -- ^ where pen pressed 
                     -> UTCTime
                     -> MainCoroutine ()
startWidgetAction mode cid geometry (sfc,sfc2)
                  owxy@(CvsCoord (xw,yw)) oxy@(CvsCoord (x0,y0)) otime = do
  r <- nextevent
  case r of 
    PenMove _ pcoord -> do 
      ctime <- liftIO getCurrentTime 
      let dtime = diffUTCTime ctime otime 
          willUpdate = dtime > dtime_bound 
      when willUpdate $ 
        movingRender mode cid geometry (sfc,sfc2) owxy oxy pcoord      
      if willUpdate
        then 
          startWidgetAction mode cid geometry (sfc,sfc2) owxy oxy ctime
        else      
          startWidgetAction mode cid geometry (sfc,sfc2) owxy oxy otime
      
    PenUp _ pcoord -> do 
      
      movingRender mode cid geometry (sfc,sfc2) owxy oxy pcoord 
      case mode of 
        Zooming -> do 
          let CvsCoord (x,y) = (desktop2Canvas geometry . device2Desktop geometry) pcoord 
              ccoord@(CvsCoord (xo,yo)) = CvsCoord (xw+50,yw+50)
              (z,(xtrans,ytrans)) = findZoomXform ((xo,yo),(x0,y0),(x,y))
              nratio = zoomRatioFrmRelToCurr geometry z
              
              mpnpgxy = (desktop2Page geometry . canvas2Desktop geometry) ccoord 
              
          -- pageZoomChange (Zoom nratio) 
          canvasZoomUpdateGenRenderCvsId (return ()) cid (Just (Zoom nratio)) Nothing 
          
          case mpnpgxy of 
            Nothing -> return () 
            Just pnpgxy@(pnum,pgxy) -> do 
              xstate <- get
              let hdl = getHoodle xstate
              geometry <- liftIO $ getCanvasGeometryCvsId cid xstate
              let -- PageCoord (xp,yp) = pgxy
                  DeskCoord (xd,yd) = page2Desktop geometry pnpgxy
                  DeskCoord (xd0,yd0) = canvas2Desktop geometry ccoord 
                  DeskCoord (xco,yco) = canvas2Desktop geometry (CvsCoord (0,0))
                  -- npgxy =  PageCoord (xp-(xd0-xco),yp-(yd0-yco))
                  -- npnpgxy = (pnum,npgxy)
                  act xst =  
                    let cinfobox = getCanvasInfo cid xst 
                        nwpos = CvsCoord (xw+x-x0,yw+y-y0)
                        moveact :: (ViewMode a) => CanvasInfo a -> CanvasInfo a 
                        moveact cinfo = 
                          let BBox (xorig0,yorig0) _ = unViewPortBBox $ view (viewInfo.pageArrangement.viewPortBBox) cinfo
                              DesktopDimension ddim = view (viewInfo.pageArrangement.desktopDimension) cinfo
                              {- zmode = view (viewInfo.zoomMode) cinfo
                              cdim = canvasDim geometry 
                              narr = makeContinousArrangement zmode cdim npgpgxy -}
                          in over (viewInfo.pageArrangement.viewPortBBox) (applyGuard ddim (moveBBoxULCornerTo (xorig0+xd-xd0,yorig0+yd-yd0))) $ cinfo
                        ncinfobox = selectBox moveact moveact cinfobox       
                    in setCanvasInfo (cid,ncinfobox) xst
                  
              updateXState (return . act) 
              -- canvasZoomUpdateAll
              adjustScrollbarWithGeometryCvsId cid 
              
              liftIO $putStrLn "IWKIMTEST"
              liftIO$ print (xd0,yd0,xd,yd)
              -- invalidateAll 
              -- canvasZoomUpdateGenRenderCvsId invalidateAll cid Nothing (Just npnpgxy)    
              -- return ()     
        _ -> return ()
      invalidate cid 
      
      -- IWKIM
      test_xstate <- get
      test_geometry <- liftIO $ getCanvasGeometryCvsId cid test_xstate
      let test_dcoord = canvas2Desktop test_geometry (CvsCoord (0,0))
      liftIO $ print "test IWKIIIIM"
      liftIO (print test_dcoord)
      -- ENDIWKIM

      
    _ -> startWidgetAction mode cid geometry (sfc,sfc2) owxy oxy otime


movingRender mode cid geometry (sfc,sfc2) owxy@(CvsCoord (xw,yw)) oxy@(CvsCoord (x0,y0)) pcoord = do 
          let CvsCoord (x,y) = (desktop2Canvas geometry . device2Desktop geometry) pcoord 
          xst <- get 
          case mode of
            Moving -> do 
              let cinfobox = getCanvasInfo cid xst 
                  nwpos = CvsCoord (xw+x-x0,yw+y-y0)
              
                  changeact :: (ViewMode a) => CanvasInfo a -> CanvasInfo a 
                  changeact cinfo =  
                    set (canvasWidgets.testWidgetPosition) nwpos $ cinfo
                  ncinfobox = selectBox changeact changeact  cinfobox
              put (setCanvasInfo (cid,ncinfobox) xst)
              renderWith sfc2 $ do 
                setSourceSurface sfc 0 0 
                setOperator OperatorSource 
                paint
                setOperator OperatorOver
                renderTestWidget Nothing nwpos 
              
            Zooming -> do -- return () 
              let cinfobox = getCanvasInfo cid xst               
              let pos = runIdentity (boxAction (return . view (canvasWidgets.testWidgetPosition)) cinfobox )
              let (xo,yo) = (xw+50,yw+50)
                  (z,(xtrans,ytrans)) = findZoomXform ((xo,yo),(x0,y0),(x,y)) 
              renderWith sfc2 $ do 
                  save
                  scale z z
                  translate xtrans ytrans 
                  setSourceSurface sfc 0 0 
                  setOperator OperatorSource 
                  paint
                  setOperator OperatorOver
                  restore
                  renderTestWidget Nothing pos 
              
          xst2 <- get 
          let cinfobox = getCanvasInfo cid xst2 
              drawact :: (ViewMode a) => CanvasInfo a -> IO ()
              drawact cinfo = do 
                let canvas = view drawArea cinfo 
                    pos = view (canvasWidgets.testWidgetPosition) cinfo
                win <- widgetGetDrawWindow canvas
                renderWithDrawable win $ do 
                  setSourceSurface sfc2 0 0 
                  setOperator OperatorSource 
                  paint
          liftIO $ boxAction drawact cinfobox