{-# LANGUAGE OverloadedStrings #-}

-----------------------------------------------------------------------------
-- |
-- Module      : Hoodle.Coroutine.Select.Transform
-- Copyright   : (c) 2011-2013 Ian-Woo Kim
--
-- License     : BSD3
-- Maintainer  : Ian-Woo Kim <ianwookim@gmail.com>
-- Stability   : experimental
-- Portability : GHC
--
-----------------------------------------------------------------------------

module Hoodle.Coroutine.Select.Transform where

-- from other packages
import Control.Lens 
import Control.Monad.State 
import Control.Monad.Trans
-- from hoodle-platform 
import Data.Hoodle.Generic
import Data.Hoodle.Select 
import Graphics.Hoodle.Render.Type.Hoodle
-- from this package
import Hoodle.Coroutine.Draw 
import Hoodle.Coroutine.Commit 
import Hoodle.ModelAction.Page 
import Hoodle.ModelAction.Select
import Hoodle.ModelAction.Select.Transform
import Hoodle.Type.Coroutine
import Hoodle.Type.HoodleState 
-- 

data RotateDirection = CW | CCW 
                     deriving (Show,Eq,Ord)
                              

rotateSelection :: RotateDirection -> MainCoroutine () 
rotateSelection dir = do 
    liftIO $ putStrLn "rotateSelection"
    either (const (return ())) action 
      . hoodleModeStateEither 
      . view hoodleModeState =<< get 

  where action thdl = do 
          xst <- get 
          case view gselSelected thdl of 
            Nothing -> return () 
            Just (n,tpg) -> do 
              let ntpg = changeSelectionByOffset (10,10) tpg 
              nthdl <- liftIO $ updateTempHoodleSelectIO thdl ntpg n
              commit . set hoodleModeState (SelectState nthdl)
                =<< (liftIO (updatePageAll (SelectState nthdl) xst))
              invalidateAll 
--              rItmsInActiveLyr 
              
              
--              let hititms = (map rItem2Item . getSelectedItms) tpg  
