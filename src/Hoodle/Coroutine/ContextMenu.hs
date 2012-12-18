{-# LANGUAGE OverloadedStrings #-}

-----------------------------------------------------------------------------
-- |
-- Module      : Hoodle.Coroutine.ContextMenu
-- Copyright   : (c) 2012 Ian-Woo Kim
--
-- License     : BSD3
-- Maintainer  : Ian-Woo Kim <ianwookim@gmail.com>
-- Stability   : experimental
-- Portability : GHC
--
-----------------------------------------------------------------------------

module Hoodle.Coroutine.ContextMenu where

-- from other packages
import           Control.Category
import           Control.Lens
import           Control.Monad.State
import           Data.ByteString.Char8 as B (pack)
import qualified Data.ByteString.Lazy as L
import qualified Data.IntMap as IM
import           Data.Monoid
import           Graphics.Rendering.Cairo
import           Graphics.UI.Gtk hiding (get,set)
import           System.Directory
import           System.FilePath
-- from hoodle-platform
import           Control.Monad.Trans.Crtn.Event
import           Control.Monad.Trans.Crtn.Queue 
import           Data.Hoodle.BBox
import           Data.Hoodle.Generic
import           Data.Hoodle.Simple
import           Data.Hoodle.Select
import           Graphics.Hoodle.Render
-- import           Graphics.Hoodle.Render.Generic
-- import           Graphics.Hoodle.Render.Item
import           Graphics.Hoodle.Render.Type
import           Graphics.Hoodle.Render.Type.HitTest 
-- import           Text.Hoodle.Builder 
-- from this package 
import           Hoodle.Accessor
import           Hoodle.Coroutine.Draw
import           Hoodle.Coroutine.File
import           Hoodle.Coroutine.Scroll
import           Hoodle.Coroutine.Select.Clipboard 
import           Hoodle.ModelAction.Page 
import           Hoodle.Type.Canvas
import           Hoodle.Type.Coroutine
import           Hoodle.Type.Event
import           Hoodle.Type.HoodleState
import           Hoodle.Type.PageArrangement 
--
import Prelude hiding ((.),id)

processContextMenu :: ContextMenuEvent -> MainCoroutine () 
processContextMenu (CMenuSaveSelectionAs ityp) = do 
  xstate <- get
  case view hoodleModeState xstate of 
    SelectState thdl -> do 
      liftIO $ putStrLn "SelectState"
      case view gselSelected thdl of 
        Nothing -> return () 
        Just (_,tpg) -> do 
          let ealist = unTEitherAlterHitted 
                       . view gitems . view selectedLayer . view glayers $ tpg 
          case ealist of 
            Right alist -> do 
              let hititms = concatMap unHitted (getB alist) 
                  ulbbox = unUnion . mconcat . fmap (Union . Middle . getBBox) 
                           $ hititms 
              case ulbbox of 
                Middle bbox -> 
                  case ityp of 
                    SVG -> exportCurrentSelectionAsSVG hititms bbox
                    PDF -> exportCurrentSelectionAsPDF hititms bbox
                _ -> return () 
            Left _ -> do liftIO $ putStrLn "not exist"
    _ -> return () 
processContextMenu CMenuCut = cutSelection
processContextMenu CMenuCopy = copySelection
processContextMenu CMenuDelete = deleteSelection
processContextMenu (CMenuCanvasView cid pnum x y) = do 
    liftIO $ print (cid,pnum,x,y)
    xstate <- get 
    let cmap = view cvsInfoMap xstate 
    let mcinfobox = IM.lookup cid cmap 
    case mcinfobox of 
      Nothing -> liftIO $ putStrLn "what?"
      Just cinfobox -> do 
        liftIO $ putStrLn "okay"
        -- let cinfobox'= selectBox single cont cinfobox 
        cinfobox' <- liftIO (setPage xstate pnum cid)
        put $ set cvsInfoMap (IM.adjust (const cinfobox') cid cmap) xstate 
        adjustScrollbarWithGeometryCvsId cid 
        invalidateAll 
--   where single = over currentPageNum (const pnum) 
--         cont = over currentPageNum (const pnum) 
{-      
  where scrollmovecanvas v cvsInfo = 
          let BBox vm_orig _ = unViewPortBBox $ view (viewInfo.pageArrangement.viewPortBBox) cvsInfo
          in over (viewInfo.pageArrangement.viewPortBBox) 
                  (apply (moveBBoxULCornerTo (fst vm_orig,v))) cvsInfo 
             
        scrollmovecanvasCont geometry v cvsInfo = 
          let BBox vm_orig _ = unViewPortBBox $ view (viewInfo.pageArrangement.viewPortBBox) cvsInfo
              cpn = PageNum . view currentPageNum $ cvsInfo 
              ncpn = maybe cpn fst $ desktop2Page geometry (DeskCoord (0,v))
          in  over currentPageNum (const (unPageNum ncpn)) 
              . over (viewInfo.pageArrangement.viewPortBBox) 
                       (apply (moveBBoxULCornerTo (fst vm_orig,v))) $ cvsInfo 
-}
  

exportCurrentSelectionAsSVG :: [RItem] -> BBox -> MainCoroutine () 
exportCurrentSelectionAsSVG hititms bbox@(BBox (ulx,uly) (lrx,lry)) = 
    fileChooser FileChooserActionSave >>= maybe (return ()) action 
  where 
    action filename =
      -- this is rather temporary not to make mistake 
      if takeExtension filename /= ".svg" 
      then fileExtensionInvalid (".svg","export") 
           >> exportCurrentSelectionAsSVG hititms bbox
      else do      
        liftIO $ print "exportCurrentSelectionAsSVG executed"
        liftIO $ withSVGSurface filename (lrx-ulx) (lry-uly) $ \s -> renderWith s $ do 
          translate (-ulx) (-uly)
          mapM_ renderRItem  hititms


exportCurrentSelectionAsPDF :: [RItem] -> BBox -> MainCoroutine () 
exportCurrentSelectionAsPDF hititms bbox@(BBox (ulx,uly) (lrx,lry)) = 
    fileChooser FileChooserActionSave >>= maybe (return ()) action 
  where 
    action filename =
      -- this is rather temporary not to make mistake 
      if takeExtension filename /= ".pdf" 
      then fileExtensionInvalid (".svg","export") 
           >> exportCurrentSelectionAsPDF hititms bbox
      else do      
        liftIO $ print "exportCurrentSelectionAsPDF executed"
        liftIO $ withPDFSurface filename (lrx-ulx) (lry-uly) $ \s -> renderWith s $ do 
          translate (-ulx) (-uly)
          mapM_ renderRItem  hititms


showContextMenu :: (PageNum,(Double,Double)) -> MainCoroutine () 
showContextMenu (pnum,(x,y)) = do 
    xstate <- get
    let cids = IM.keys . view cvsInfoMap $ xstate
        cid = fst . view currentCanvas $ xstate 
    modify (tempQueue %~ enqueue (action cid cids)) 
    >> waitSomeEvent (==ContextMenuCreated) 
    >> return () 
  where action cid cids  
          = Left . ActionOrder $ 
              \evhandler -> do 
                menu <- menuNew 
                menuSetTitle menu "MyMenu"
                menuitem1 <- menuItemNewWithLabel "Make SVG"
                menuitem2 <- menuItemNewWithLabel "Make PDF"
                menuitem3 <- menuItemNewWithLabel "Cut"
                menuitem4 <- menuItemNewWithLabel "Copy"
                menuitem5 <- menuItemNewWithLabel "Delete"
                menuitem1 `on` menuItemActivate $   
                  evhandler (GotContextMenuSignal (CMenuSaveSelectionAs SVG))
                menuitem2 `on` menuItemActivate $ 
                  evhandler (GotContextMenuSignal (CMenuSaveSelectionAs PDF))
                menuitem3 `on` menuItemActivate $ 
                  evhandler (GotContextMenuSignal (CMenuCut))     
                menuitem4 `on` menuItemActivate $    
                  evhandler (GotContextMenuSignal (CMenuCopy))
                menuitem5 `on` menuItemActivate $    
                  evhandler (GotContextMenuSignal (CMenuDelete))     
                menuAttach menu menuitem1 0 1 0 1 
                menuAttach menu menuitem2 0 1 1 2
                menuAttach menu menuitem3 1 2 0 1                     
                menuAttach menu menuitem4 1 2 1 2                     
                menuAttach menu menuitem5 1 2 2 3    
                runStateT (mapM_ (makeMenu evhandler menu cid) cids) 0 
                widgetShowAll menu 
                menuPopup menu Nothing 
                putStrLn "showContextMenu"
                return ContextMenuCreated 

        makeMenu evhdlr mn currcid cid 
          = when (currcid /= cid) $ do 
              n <- get
              mi <- liftIO $ menuItemNewWithLabel (show cid)
              liftIO $ mi `on` menuItemActivate $ 
                evhdlr (GotContextMenuSignal (CMenuCanvasView cid pnum x y)) 
              liftIO $ menuAttach mn mi 2 3 n (n+1) 
              put (n+1) 
    