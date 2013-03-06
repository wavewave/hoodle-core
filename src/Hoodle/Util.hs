{-# LANGUAGE OverloadedStrings #-}

-----------------------------------------------------------------------------
-- |
-- Module      : Hoodle.Util 
-- Copyright   : (c) 2013 Ian-Woo Kim
--
-- License     : BSD3
-- Maintainer  : Ian-Woo Kim <ianwookim@gmail.com>
-- Stability   : experimental
-- Portability : GHC
--
-----------------------------------------------------------------------------

module Hoodle.Util where

import Control.Applicative 
import Data.Attoparsec.Char8 
import qualified Data.ByteString.Char8 as B
import Data.Maybe
import Network.URI

import System.Directory 
import System.Environment 
import System.FilePath
import System.IO
import Data.Time.Clock 
import Data.Time.Format
import System.Locale
-- 
import Data.Hoodle.Simple



-- for test
-- import Blaze.ByteString.Builder
-- import Text.Hoodle.Builder 

{-
testPage :: Page Edit -> IO () 
testPage page = do
    let pagesimple = toPage bkgFromBkgPDF . tpageBBoxMapPDFFromTPageBBoxMapPDFBuf $ page 
    L.putStrLn . toLazyByteString . Text.Hoodle.Builder.fromPage $ pagesimple 
-}

             
{-
testHoodle :: HoodleState -> IO () 
testHoodle hdlstate = do
  let hdlsimple :: Hoodle = case hdlstate of
                               ViewAppendState hdl -> xournalFromTHoodleSimple (gcast hdl :: THoodleSimple)
                               SelectState thdl -> xournalFromTHoodleSimple (gcast thdl :: THoodleSimple)
  L.putStrLn (builder hdlsimple)
-}

(#) :: a -> (a -> b) -> b 
(#) = flip ($)
infixr 0 #

maybeFlip :: Maybe a -> b -> (a->b) -> b  
maybeFlip m n j = maybe n j m   

uncurry4 :: (a->b->c->d->e)->(a,b,c,d)->e 
uncurry4 f (x,y,z,w) = f x y z w 

maybeRead :: Read a => String -> Maybe a 
maybeRead = fmap fst . listToMaybe . reads 


getLargestWidth :: Hoodle -> Double 
getLargestWidth hdl = 
  let ws = map (dim_width . page_dim) (hoodle_pages hdl)  
  in  maximum ws 

getLargestHeight :: Hoodle -> Double 
getLargestHeight hdl = 
  let hs = map (dim_height . page_dim) (hoodle_pages hdl)  
  in  maximum hs 

waitUntil :: (Monad m) => (a -> Bool) -> m a -> m ()
waitUntil p act = do 
  a <- act
  if p a
    then return ()
    else waitUntil p act  

-- | for debugging
errorlog :: String -> IO ()
errorlog str = do 
  homepath <- getEnv "HOME"
  let dir = homepath </> ".hoodle.d"
  createDirectoryIfMissing False dir
  outh <- openFile (dir </> "error.log") AppendMode 
  utctime <- getCurrentTime 
  let timestr = formatTime defaultTimeLocale "%F %H:%M:%S %Z" utctime
  hPutStr outh (timestr ++ " : " )  
  hPutStrLn outh str
  hClose outh 

-- | 
maybeError' :: String -> Maybe a -> a
maybeError' str = maybe (error str) id



data UrlPath = FileUrl FilePath 

-- | 
urlParse :: String -> Maybe UrlPath 
urlParse str = 
  if length str < 7 
    then Just (FileUrl str) 
    else 
      let p = string "file://" *> manyTill anyChar (satisfy (inClass "\r\n"))
          r = parseOnly p (B.pack str)
      in case r of 
           Left _ -> Just (FileUrl str) 
           Right f -> Just (FileUrl (unEscapeString f))
    
    
{-    
    case str of
    
           _ -> Just (FileUrl str) 
-}
    
    
    {- 
           'f':'i':'l':'e':':':'/':'/':fp -> Just (FileUrl (head (lines fp)))
 -}

{-
timeShow :: String -> IO () 
timeShow msg = 
  putStrLn . (msg ++) . (formatTime defaultTimeLocale "%Q") 
    =<< getCurrentTime 
-}