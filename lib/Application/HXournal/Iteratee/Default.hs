module Application.HXournal.Iteratee.Default where

import Graphics.UI.Gtk hiding (get,set)

import Application.HXournal.Type.Event
import Application.HXournal.Type.Coroutine
import Application.HXournal.Type.Canvas
import Application.HXournal.Type.XournalState
import Graphics.Xournal.Render.BBox
import Application.HXournal.Draw
import Application.HXournal.Accessor

import Application.HXournal.Iteratee.Draw 
import Application.HXournal.Iteratee.Pen 
import Application.HXournal.Iteratee.Eraser
import Application.HXournal.Iteratee.Highlighter
import Application.HXournal.Iteratee.Scroll
import Application.HXournal.Iteratee.Page
import Application.HXournal.Iteratee.Select

import Application.HXournal.Builder 

import Control.Applicative 
import Control.Monad.Coroutine
import Control.Monad.Coroutine.SuspensionFunctors
import qualified Control.Monad.State as St 

import Control.Monad.Trans

import qualified Data.Map as M
import Data.Maybe
import qualified Data.ByteString.Lazy as L
import Control.Category
import Data.Label
import Prelude hiding ((.), id)

import Text.Xournal.Type 


guiProcess :: Iteratee MyEvent XournalStateIO () 
guiProcess = do 
  initialize
  changePage (const 0)
  xstate <- lift St.get
  let cinfoMap  = get canvasInfoMap xstate
      assocs = M.toList cinfoMap 
      f (cid,cinfo) = do let canvas = get drawArea cinfo
                         (w',h') <- liftIO $ widgetGetSize canvas
                         defaultEventProcess (CanvasConfigure cid
                                                (fromIntegral w') 
                                                (fromIntegral h')) 
  mapM_ f assocs
  sequence_ (repeat eventProcess)

initialize :: Iteratee MyEvent XournalStateIO ()
initialize = do ev <- await 
                liftIO $ putStrLn $ show ev 
                case ev of 
                  Initialized -> return () 
                  _ -> initialize

eventProcess :: Iteratee MyEvent XournalStateIO ()
eventProcess = do 
  r1 <- await 
  case r1 of 
    PenDown cid pcoord -> do 
      ptype <- getPenType 
      case ptype of 
        PenWork         -> penStart cid pcoord 
        EraserWork      -> eraserStart cid pcoord 
        HighlighterWork -> highlighterStart pcoord 
    _ -> defaultEventProcess r1

defaultEventProcess :: MyEvent -> Iteratee MyEvent XournalStateIO () 
defaultEventProcess (UpdateCanvas cid) = invalidate cid   
defaultEventProcess MenuQuit = liftIO $ mainQuit
defaultEventProcess MenuPreviousPage = changePage (\x->x-1)
defaultEventProcess MenuNextPage =  changePage (+1)
defaultEventProcess MenuFirstPage = changePage (const 0)
defaultEventProcess MenuLastPage = changePage (const 10000)
defaultEventProcess MenuSave = do 
    xojcontent <- unView . get xournalstate <$> lift St.get   
    liftIO $ L.writeFile "mytest.xoj" . builder . xournalFromXournalBBox 
           $ xojcontent
defaultEventProcess MenuNormalSize = do 
    liftIO $ putStrLn "NormalSize clicked"
    xstate <- lift St.get 
    let currCvsId = get currentCanvas xstate
        cinfoMap = get canvasInfoMap xstate
        maybeCurrCvs = M.lookup currCvsId cinfoMap 
    case maybeCurrCvs of 
      Nothing -> return ()
      Just currCvsInfo -> do 
        let canvas = get drawArea currCvsInfo
        (w',h') <- liftIO $ widgetGetSize canvas
        let cpn = get currentPageNum currCvsInfo
        let Dim w h = pageDim . (!! cpn) . xournalPages . unView 
                    . get xournalstate 
                    $ xstate
        let (hadj,vadj) = get adjustments currCvsInfo 
        liftIO $ do 
          adjustmentSetUpper hadj w 
          adjustmentSetUpper vadj h 
          adjustmentSetValue hadj 0 
          adjustmentSetValue vadj 0 
          adjustmentSetPageSize hadj (fromIntegral w')
          adjustmentSetPageSize vadj (fromIntegral h')
        let currCvsInfo' = set (zoomMode.viewInfo) Original
                         . set (viewPortOrigin.viewInfo) (0,0)
                         $ currCvsInfo 
            cinfoMap' = M.adjust (\_ -> currCvsInfo') currCvsId cinfoMap  
            xstate' = set canvasInfoMap cinfoMap' xstate
        lift . St.put $ xstate' 
        invalidate currCvsId       
defaultEventProcess MenuPageWidth = do 
    liftIO $ putStrLn "PageWidth clicked"
    xstate <- lift St.get 
    let currCvsId = get currentCanvas xstate
        cinfoMap = get canvasInfoMap xstate
        maybeCurrCvs = M.lookup currCvsId cinfoMap 
    case maybeCurrCvs of 
      Nothing -> return ()
      Just currCvsInfo -> do 
        let canvas = get drawArea currCvsInfo
            cpn = get currentPageNum currCvsInfo
            page = (!! cpn) . xournalPages . unView . get xournalstate $ xstate
            Dim w h = pageDim page 
        cpg <- liftIO (getCanvasPageGeometry canvas page (0,0))
        let (w',h') = canvas_size cpg 
        let (hadj,vadj) = get adjustments currCvsInfo 
            s = 1.0 / getRatioFromPageToCanvas cpg FitWidth 
        liftIO $ do 
          adjustmentSetUpper hadj w 
          adjustmentSetUpper vadj h 
          adjustmentSetValue hadj 0 
          adjustmentSetValue vadj 0 
          adjustmentSetPageSize hadj (w'*s)
          adjustmentSetPageSize vadj (h'*s)
        let currCvsInfo' = set (zoomMode.viewInfo) FitWidth          
                         . set (viewPortOrigin.viewInfo) (0,0) 
                         $ currCvsInfo
            cinfoMap' = M.adjust (\_ -> currCvsInfo') currCvsId cinfoMap  
            xstate' = set canvasInfoMap cinfoMap' xstate
        lift . St.put $ xstate'             
        invalidate currCvsId    
defaultEventProcess MenuSelectRectangle = do 
    xstate <- lift St.get 
    let currCvsId = get currentCanvas xstate
    selectStart currCvsId 
defaultEventProcess (HScrollBarMoved cid v) = do 
    xstate <- lift St.get 
    let cinfoMap = get canvasInfoMap xstate
        maybeCvs = M.lookup cid cinfoMap 
    case maybeCvs of 
      Nothing -> return ()
      Just cvsInfo -> do 
        let vm_orig = get (viewPortOrigin.viewInfo) cvsInfo
        let cvsInfo' = set (viewPortOrigin.viewInfo) (v,snd vm_orig) 
                         $ cvsInfo
            cinfoMap' = M.adjust (\_ -> cvsInfo') cid cinfoMap  
            xstate' = set canvasInfoMap cinfoMap' 
                    . set currentCanvas cid 
                    $ xstate
        lift . St.put $ xstate'
        invalidate cid
defaultEventProcess (VScrollBarMoved cid v) = do 
    xstate <- lift St.get 
    let cinfoMap = get canvasInfoMap xstate
        maybeCvs = M.lookup cid cinfoMap 
    case maybeCvs of 
      Nothing -> return ()
      Just cvsInfo -> do 
        let vm_orig = get (viewPortOrigin.viewInfo) cvsInfo
        let cvsInfo' = set (viewPortOrigin.viewInfo) (fst vm_orig,v)
                         $ cvsInfo 
            cinfoMap' = M.adjust (\_ -> cvsInfo') cid cinfoMap  
            xstate' = set canvasInfoMap cinfoMap' 
                    . set currentCanvas cid
                    $ xstate
        lift . St.put $ xstate'
        invalidate cid
defaultEventProcess (VScrollBarStart cid v) = do 
  vscrollStart cid 

defaultEventProcess (CanvasConfigure cid w' h') = do 
    xstate <- lift St.get 
    let -- currCvsId = get currentCanvas xstate
        cinfoMap = get canvasInfoMap xstate
        maybeCvs = M.lookup cid cinfoMap 
    case maybeCvs of 
      Nothing -> return ()
      Just cvsInfo -> do 
        let canvas = get drawArea cvsInfo
            cpn = get currentPageNum cvsInfo
            page = (!! cpn) . xournalPages . unView . get xournalstate $ xstate
            (w,h) = get (pageDimension.viewInfo) cvsInfo
            zmode = get (zoomMode.viewInfo) cvsInfo
        cpg <- liftIO (getCanvasPageGeometry canvas page (0,0))
        let factor = getRatioFromPageToCanvas cpg zmode
            (hadj,vadj) = get adjustments cvsInfo
        liftIO $ do 
          adjustmentSetUpper hadj w 
          adjustmentSetUpper vadj h 
          adjustmentSetLower hadj 0
          adjustmentSetLower vadj 0
          adjustmentSetValue hadj 0
          adjustmentSetValue vadj 0 
          adjustmentSetPageSize hadj (w'/factor)
          adjustmentSetPageSize vadj (h'/factor)
        invalidate cid
        return () 
defaultEventProcess _ = return ()