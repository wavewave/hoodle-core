{-# LANGUAGE OverloadedStrings #-}

-----------------------------------------------------------------------------
-- |
-- Module      : Hoodle.Coroutine.File 
-- Copyright   : (c) 2011, 2012 Ian-Woo Kim
--
-- License     : BSD3
-- Maintainer  : Ian-Woo Kim <ianwookim@gmail.com>
-- Stability   : experimental
-- Portability : GHC
--
-----------------------------------------------------------------------------

module Hoodle.Coroutine.File where

-- from other packages
import           Control.Category
import           Control.Lens
import           Control.Monad.State
import           Data.ByteString.Char8 as B (pack)
import qualified Data.ByteString.Lazy as L
import qualified Data.IntMap as IM
import           Graphics.Rendering.Cairo
import           Graphics.UI.Gtk hiding (get,set)
import           System.Directory
import           System.FilePath
-- from hoodle-platform
import           Control.Monad.Trans.Crtn.Event
import           Control.Monad.Trans.Crtn.Queue 
import           Data.Hoodle.Generic
import           Data.Hoodle.Simple
import           Data.Hoodle.Select
-- import           Graphics.Hoodle.Render
import           Graphics.Hoodle.Render.Generic
import           Graphics.Hoodle.Render.Item
import           Graphics.Hoodle.Render.Type
import           Graphics.Hoodle.Render.Type.HitTest 
import           Text.Hoodle.Builder 
-- from this package 
import           Hoodle.Coroutine.Draw
import           Hoodle.Coroutine.Commit
import           Hoodle.Coroutine.Mode 
import           Hoodle.ModelAction.File
import           Hoodle.ModelAction.Layer 
import           Hoodle.ModelAction.Page
import           Hoodle.ModelAction.Select
import           Hoodle.ModelAction.Window
import qualified Hoodle.Script.Coroutine as S
import           Hoodle.Script.Hook
import           Hoodle.Type.Canvas
import           Hoodle.Type.Coroutine
import           Hoodle.Type.Event
import           Hoodle.Type.HoodleState
--
import Prelude hiding ((.),id)

-- |
okMessageBox :: String -> MainCoroutine () 
okMessageBox msg = modify (tempQueue %~ enqueue action) >> go 
  where 
    go = do r <- nextevent                   
            case r of 
              GotOk -> return ()  
              _ -> go 
    action = Left . ActionOrder $ 
               \_evhandler -> do 
                 dialog <- messageDialogNew Nothing [DialogModal]
                   MessageQuestion ButtonsOk msg 
                 _res <- dialogRun dialog 
                 widgetDestroy dialog 
                 return GotOk 

-- | 
okCancelMessageBox :: String -> MainCoroutine Bool 
okCancelMessageBox msg = modify (tempQueue %~ enqueue action) >> go 
  where 
    action = Left . ActionOrder $ 
               \_evhandler -> do 
                 dialog <- messageDialogNew Nothing [DialogModal]
                   MessageQuestion ButtonsOkCancel msg 
                 res <- dialogRun dialog 
                 let b = case res of 
                           ResponseOk -> True
                           _ -> False
                 widgetDestroy dialog 
                 return (OkCancel b)
    go = do r <- nextevent                   
            case r of 
              OkCancel b -> return b  
              _ -> go 

-- | 
fileChooser :: FileChooserAction -> MainCoroutine (Maybe FilePath) 
fileChooser choosertyp = modify (tempQueue %~ enqueue action) >> go 
  where 
    go = do r <- nextevent                   
            case r of 
              FileChosen b -> return b  
              _ -> go 
    action = Left . ActionOrder $ \_evhandler -> do 
      dialog <- fileChooserDialogNew Nothing Nothing choosertyp 
                  [ ("OK", ResponseOk) 
                  , ("Cancel", ResponseCancel) ]
      cwd <- getCurrentDirectory                  
      fileChooserSetCurrentFolder dialog cwd 
      res <- dialogRun dialog
      mr <- case res of 
              ResponseDeleteEvent -> return Nothing
              ResponseOk ->  fileChooserGetFilename dialog 
              ResponseCancel -> return Nothing 
              _ -> putStrLn "??? in fileOpen" >> return Nothing 
      widgetDestroy dialog
      return (FileChosen mr)

-- | 
askIfSave :: MainCoroutine () -> MainCoroutine () 
askIfSave action = do 
    xstate <- get 
    if not (view isSaved xstate)
      then do  
        b <- okCancelMessageBox "Current canvas is not saved yet. Will you proceed without save?" 
        case b of 
          True -> action 
          False -> return () 
      else action 

-- | 
fileNew :: MainCoroutine () 
fileNew = do  
    xstate <- get
    xstate' <- liftIO $ getFileContent Nothing xstate 
    ncvsinfo <- liftIO $ setPage xstate' 0 (getCurrentCanvasId xstate')
    xstate'' <- return $ over currentCanvasInfo (const ncvsinfo) xstate'
    liftIO $ setTitleFromFileName xstate''
    commit xstate'' 
    invalidateAll 

-- | 
fileSave :: MainCoroutine ()
fileSave = do 
    xstate <- get 
    case view currFileName xstate of
      Nothing -> fileSaveAs 
      Just filename -> do     
        -- this is rather temporary not to make mistake 
        if takeExtension filename == ".hdl" 
          then do 
             let hdl = (rHoodle2Hoodle . getHoodle) xstate 
             liftIO . L.writeFile filename . builder $ hdl
             put . set isSaved True $ xstate 
             let ui = view gtkUIManager xstate
             liftIO $ toggleSave ui False
             S.afterSaveHook hdl
           else fileExtensionInvalid (".hdl","save") >> fileSaveAs 


-- | interleaving a monadic action between each pair of subsequent actions
sequence1_ :: (Monad m) => m () -> [m ()] -> m () 
sequence1_ _ []  = return () 
sequence1_ _ [a] = a 
sequence1_ i (a:as) = a >> i >> sequence1_ i as 

-- | 
renderjob :: RHoodle -> FilePath -> IO () 
renderjob h ofp = do 
  let p = maybe (error "renderjob") id $ IM.lookup 0 (view gpages h)  
  let Dim width height = view gdimension p  
  let rf = cairoRenderOption (InBBoxOption Nothing) :: InBBox RPage -> Render ()
  withPDFSurface ofp width height $ \s -> renderWith s $  
    -- (sequence1_ showPage . map renderPage . hoodle_pages) h 
    (sequence1_ showPage . map (rf . InBBox) . IM.elems . view gpages ) h 

-- | 
fileExport :: MainCoroutine ()
fileExport = fileChooser FileChooserActionSave >>= maybe (return ()) action 
  where 
    action filename = 
      -- this is rather temporary not to make mistake 
      if takeExtension filename /= ".pdf" 
      then fileExtensionInvalid (".pdf","export") >> fileExport 
      else do      
        xstate <- get 
        let hdl = getHoodle xstate -- (rHoodle2Hoodle . getHoodle) xstate 
        liftIO (renderjob hdl filename) 


-- | 
fileLoad :: FilePath -> MainCoroutine () 
fileLoad filename = do
    xstate <- get 
    xstate' <- liftIO $ getFileContent (Just filename) xstate
    ncvsinfo <- liftIO $ setPage xstate' 0 (getCurrentCanvasId xstate')
    xstateNew <- return $ over currentCanvasInfo (const ncvsinfo) xstate'
    put . set isSaved True 
      $ xstateNew 
    liftIO $ setTitleFromFileName xstateNew  
    clearUndoHistory 
    invalidateAll 


-- | main coroutine for open a file 
fileOpen :: MainCoroutine ()
fileOpen = do 
  mfilename <- fileChooser FileChooserActionOpen
  case mfilename of 
    Nothing -> return ()
    Just filename -> fileLoad filename 

-- | main coroutine for save as 
fileSaveAs :: MainCoroutine () 
fileSaveAs = do 
    xstate <- get 
    let hdl = (rHoodle2Hoodle . getHoodle) xstate
    maybe (defSaveAsAction xstate hdl) (\f -> liftIO (f hdl))
          (hookSaveAsAction xstate) 
  where 
    hookSaveAsAction xstate = do 
      hset <- view hookSet xstate
      saveAsHook hset
    defSaveAsAction xstate hdl = 
        fileChooser FileChooserActionSave 
        >>= maybe (return ()) (action xstate hdl) 
      where action xst' hd filename = 
              if takeExtension filename /= ".hdl" 
              then fileExtensionInvalid (".hdl","save")
              else do 
                let ntitle = B.pack . snd . splitFileName $ filename 
                    (hdlmodst',hdl') = case view hoodleModeState xst' of
                       ViewAppendState hdlmap -> 
                         if view gtitle hdlmap == "untitled"
                           then ( ViewAppendState . set gtitle ntitle
                                  $ hdlmap
                                , (set title ntitle hd))
                           else (ViewAppendState hdlmap,hd)
                       SelectState thdl -> 
                         if view gselTitle thdl == "untitled"
                           then ( SelectState $ set gselTitle ntitle thdl 
                                , set title ntitle hd)  
                           else (SelectState thdl,hd)
                    xstateNew = set currFileName (Just filename) 
                              . set hoodleModeState hdlmodst' $ xst'
                liftIO . L.writeFile filename . builder $ hdl'
                put . set isSaved True $ xstateNew    
                let ui = view gtkUIManager xstateNew
                liftIO $ toggleSave ui False
                liftIO $ setTitleFromFileName xstateNew 
                S.afterSaveHook hdl'
          

-- | main coroutine for open a file 
fileReload :: MainCoroutine ()
fileReload = do 
    xstate <- get
    case view currFileName xstate of 
      Nothing -> return () 
      Just filename -> do
        if not (view isSaved xstate) 
          then do
            b <- okCancelMessageBox "Discard changes and reload the file?" 
            case b of 
              True -> fileLoad filename 
              False -> return ()
          else fileLoad filename

-- | 
fileExtensionInvalid :: (String,String) -> MainCoroutine ()
fileExtensionInvalid (ext,a) = 
  okMessageBox $ "only " 
                 ++ ext 
                 ++ " extension is supported for " 
                 ++ a 
    
-- | 
fileAnnotatePDF :: MainCoroutine ()
fileAnnotatePDF = 
    fileChooser FileChooserActionOpen >>= maybe (return ()) action 
  where 
    action filename = do  
      xstate <- get 
      mhdl <- liftIO $ makeNewHoodleWithPDF filename 
      flip (maybe (return ())) mhdl $ \hdl -> do 
        xstateNew <- return . set currFileName Nothing 
                     =<< (liftIO $ constructNewHoodleStateFromHoodle hdl xstate)
        commit xstateNew 
        liftIO $ setTitleFromFileName xstateNew             
        invalidateAll  
      

-- | 
fileLoadImage :: MainCoroutine ()
fileLoadImage = do 
    fileChooser FileChooserActionOpen >>= maybe (return ()) action 
  where 
    action filename = do  
      xstate <- get 
      liftIO $ putStrLn filename 
      let pgnum = unboxGet currentPageNum . view currentCanvasInfo $ xstate
          hdl = getHoodle xstate 
          (mcurrlayer,currpage) = getCurrentLayerOrSet (getPageFromGHoodleMap pgnum hdl)
          currlayer = maybe (error "something wrong in addPDraw") id mcurrlayer 
      newitem <- (liftIO . cnstrctRItem . ItemImage) 
                 (Image (B.pack filename) (100,100) (Dim 300 300))
      let otheritems = view gitems currlayer  
      let ntpg = makePageSelectMode currpage (otheritems :- (Hitted [newitem]) :- Empty)  
      modeChange ToSelectMode 
      nxstate <- get 
      let thdl = case view hoodleModeState nxstate of
                   SelectState thdl' -> thdl'
                   _ -> error "fileLoadImage"
      nthdl <- liftIO $ updateTempHoodleSelectIO thdl ntpg pgnum 
      let nxstate2 = set hoodleModeState (SelectState nthdl) nxstate
      put nxstate2
      invalidateAll 

-- |
askQuitProgram :: MainCoroutine () 
askQuitProgram = do 
    b <- okCancelMessageBox "Current canvas is not saved yet. Will you close hoodle?" 
    case b of 
      True -> liftIO mainQuit
      False -> return ()
  
