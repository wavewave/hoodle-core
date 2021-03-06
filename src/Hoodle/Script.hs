-----------------------------------------------------------------------------
-- |
-- Module      : Hoodle.Script
-- Copyright   : (c) 2012, 2013 Ian-Woo Kim
--
-- License     : BSD3
-- Maintainer  : Ian-Woo Kim <ianwookim@gmail.com>
-- Stability   : experimental
-- Portability : GHC
--
-----------------------------------------------------------------------------

module Hoodle.Script where 

import Hoodle.Script.Hook
import Config.Dyre.Relaunch

-- | 

data ScriptConfig = ScriptConfig { message :: Maybe String 
                                 , hook :: Maybe Hook
                                 , errorMsg :: Maybe String 
                                 }  

-- | 

defaultScriptConfig :: ScriptConfig 
defaultScriptConfig = ScriptConfig Nothing Nothing Nothing

-- | 

showError :: ScriptConfig -> String -> ScriptConfig
showError cfg msg = cfg { errorMsg = Just msg } 


-- | 

relaunchApplication :: IO ()
relaunchApplication = do 
  putStrLn "relaunching hoodle!"
  relaunchMaster Nothing 
  
  