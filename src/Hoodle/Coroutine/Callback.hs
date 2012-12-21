-----------------------------------------------------------------------------
-- |
-- Module      : Hoodle.Coroutine.Callback
-- Copyright   : (c) 2011, 2012 Ian-Woo Kim
--
-- License     : BSD3
-- Maintainer  : Ian-Woo Kim <ianwookim@gmail.com>
-- Stability   : experimental
-- Portability : GHC
--
-----------------------------------------------------------------------------

module Hoodle.Coroutine.Callback where

import Control.Concurrent
import Control.Exception
import Data.Time
import System.Directory
import System.Environment
import System.FilePath
import System.Locale
import System.IO
import System.Exit
--
import Control.Monad.Trans.Crtn.Driver
import qualified Control.Monad.Trans.Crtn.EventHandler as E
-- 
import Hoodle.Util
-- 
import Prelude hiding (catch)

eventHandler :: MVar (Maybe (Driver e IO ())) -> e -> IO ()
eventHandler evar ev = E.eventHandler evar ev `catch` allexceptionproc 
    
    -- `catches` [Handler errorcall, Handler patternerr] 
  
allexceptionproc :: SomeException -> IO ()
allexceptionproc e = do errorlog (show e)
                        exitFailure
                        
 
errorcall :: ErrorCall -> IO ()
errorcall e = errorlog (show e) 

patternerr :: PatternMatchFail -> IO ()
patternerr e = errorlog (show e) 
  
