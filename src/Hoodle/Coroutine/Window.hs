{-# LANGUAGE ScopedTypeVariables #-}

-----------------------------------------------------------------------------
-- |
-- Module      : Hoodle.Coroutine.Window 
-- Copyright   : (c) 2011, 2012 Ian-Woo Kim
--
-- License     : BSD3
-- Maintainer  : Ian-Woo Kim <ianwookim@gmail.com>
-- Stability   : experimental
-- Portability : GHC
--
-----------------------------------------------------------------------------

module Hoodle.Coroutine.Window where

import           Control.Category
import           Control.Lens
import           Control.Monad.State 
import           Graphics.UI.Gtk hiding (get,set)
import qualified Data.IntMap as M
import           Data.Maybe
import           Data.Time.Clock 
--
import           Data.Hoodle.Simple (Dimension(..))
import           Data.Hoodle.Generic
--
import           Hoodle.Type.Canvas
import           Hoodle.Type.Event
import           Hoodle.Type.Window
import           Hoodle.Type.HoodleState
import           Hoodle.Type.Coroutine
import           Hoodle.Type.PageArrangement
import           Hoodle.Type.Predefined
import           Hoodle.Util
import           Hoodle.ModelAction.Window
import           Hoodle.ModelAction.Page
import           Hoodle.Coroutine.Page
import           Hoodle.Coroutine.Draw
import           Hoodle.Accessor
--
import Prelude hiding ((.),id)

-- | canvas configure with general zoom update func

canvasConfigureGenUpdate :: MainCoroutine () 
                            -> CanvasId 
                            -> CanvasDimension 
                            -> MainCoroutine () 
canvasConfigureGenUpdate updatefunc cid cdim 
  = (updateXState $ selectBoxAction fsingle fcont . getCanvasInfo cid )
    >> updatefunc 
  where fsingle cinfo = do 
          xstate <- get 
          let cinfo' = updateCanvasDimForSingle cdim cinfo 
          return $ setCanvasInfo (cid,CanvasSinglePage cinfo') xstate
        fcont cinfo = do 
          xstate <- get
          page <- getCurrentPageCvsId cid
          let pdim = PageDimension (view gdimension page)
          let cinfo' = updateCanvasDimForContSingle pdim cdim cinfo 
          return $ setCanvasInfo (cid,CanvasContPage cinfo') xstate 
  
-- | 

doCanvasConfigure :: CanvasId 
                     -> CanvasDimension 
                     -> MainCoroutine () 
doCanvasConfigure = canvasConfigureGenUpdate canvasZoomUpdateAll

-- | 

canvasConfigure' :: CanvasId -> CanvasDimension -> MainCoroutine () 
canvasConfigure' cid cdim = do
    xstate <- get 
    ctime <- liftIO getCurrentTime 
    maybe defaction (chkaction ctime) (view lastTimeCanvasConfigure xstate) 
  where defaction = do 
          ntime <- liftIO getCurrentTime
          doCanvasConfigure cid cdim          
          updateXState (return . set lastTimeCanvasConfigure (Just ntime))    
        chkaction ctime otime = do  
          let dtime = diffUTCTime ctime otime 
          if dtime > predefinedWinReconfTimeBound
             then defaction 
             else return ()


-- | 

eitherSplit :: SplitType -> MainCoroutine () 
eitherSplit stype = do
    xstate <- get
    let cmap = getCanvasInfoMap xstate
        currcid = getCurrentCanvasId xstate
        newcid = newCanvasId cmap 
        fstate = view frameState xstate
        enewfstate = splitWindow currcid (newcid,stype) fstate 
    case enewfstate of 
      Left _ -> return ()
      Right fstate' -> do 
        let cinfobox = maybeError "eitherSplit" . M.lookup currcid $ cmap 
        -- liftIO $ putStrLn "called here"
        let rtwin = view rootWindow xstate
            rtcntr = view rootContainer xstate 
        liftIO $ containerRemove rtcntr rtwin
        (xstate'',win,fstate'') <- 
          liftIO $ constructFrame' cinfobox xstate fstate'
        let xstate3 = set frameState fstate'' 
                      . set rootWindow win 
                      $ xstate''
        put xstate3 
        liftIO $ boxPackEnd rtcntr win PackGrow 0 
        liftIO $ widgetShowAll rtcntr  
        (xstate4,_wconf) <- liftIO $ eventConnect xstate3 (view frameState xstate3)
        xstate5 <- liftIO $ updatePageAll (view hoodleModeState xstate4) xstate4
        put xstate5 
        canvasZoomUpdateAll
        invalidateAll 
        -- fmap4CvsInfoBox f cinfobox --  \oldcinfo -> do 


-- | 

deleteCanvas :: MainCoroutine () 
deleteCanvas = do 
    xstate <- get
    let cmap = getCanvasInfoMap xstate
        currcid = getCurrentCanvasId xstate
        fstate = view frameState xstate
        enewfstate = removeWindow currcid fstate 
    case enewfstate of 
      Left _ -> return ()
      Right Nothing -> return ()
      Right (Just fstate') -> do 
        let -- cinfobox = maybeError "deleteCanvas" (M.lookup currcid cmap) 
            cmap' = M.delete currcid cmap
            newcurrcid = maximum (M.keys cmap')
        xstate0 <- changeCurrentCanvasId newcurrcid 
        let xstate1 = maybe xstate0 id $ setCanvasInfoMap cmap' xstate0
        put xstate1
        let rtwin = view rootWindow xstate1
            rtcntr = view rootContainer xstate1 
        liftIO $ containerRemove rtcntr rtwin
        (xstate'',win,fstate'') <- liftIO $ constructFrame xstate1 fstate'
        let xstate3 = set frameState fstate'' 
                      . set rootWindow win 
                      $ xstate''
        put xstate3
        liftIO $ boxPackEnd rtcntr win PackGrow 0 
        liftIO $ widgetShowAll rtcntr  
        (xstate4,_wconf) <- liftIO $ eventConnect xstate3 (view frameState xstate3)
        canvasZoomUpdateAll
        xstate5 <- liftIO $ updatePageAll (view hoodleModeState xstate4) xstate4
        put xstate5 
        invalidateAll 

            
-- | 
paneMoveStart :: MainCoroutine () 
paneMoveStart = do 
    ev <- nextevent 
    case ev of 
      UpdateCanvas cid -> invalidateWithBuf cid >> paneMoveStart 
      PaneMoveEnd -> do 
        -- canvasZoomUpdateAll 
        return () 
      CanvasConfigure cid w' h'-> do 
        canvasConfigureGenUpdate canvasZoomUpdateBufAll cid (CanvasDimension (Dim w' h')) 
        >> paneMoveStart
      _ -> paneMoveStart
       


-- | 

paneMoved :: MainCoroutine () 
paneMoved = do 
  liftIO $ putStrLn "pane moved called"
  
  
