{-# LANGUAGE EmptyDataDecls, GADTs, TypeOperators #-}

-----------------------------------------------------------------------------
-- |
-- Module      : Application.HXournal.Type.PageArrangement
-- Copyright   : (c) 2011, 2012 Ian-Woo Kim
--
-- License     : BSD3
-- Maintainer  : Ian-Woo Kim <ianwookim@gmail.com>
-- Stability   : experimental
-- Portability : GHC
--


module Application.HXournal.Type.PageArrangement where

import Control.Category
import Data.Xournal.Simple
import Data.Xournal.BBox
import Data.Label 
import Prelude hiding ((.),id)

class ViewMode a 

data SinglePage = SinglePage
data ContinuousSinglePage = ContinuousSinglePage

instance ViewMode SinglePage 
instance ViewMode ContinuousSinglePage

newtype PageOrigin = PageOrigin { unPageOrigin :: (Double,Double) } 

newtype PageDimension = PageDimension { unPageDimension :: Dimension } 

newtype DesktopDimension = DesktopDimension { unDesktopDimension :: Dimension }

newtype ViewPortBBox = ViewPortBBox { unViewPortBBox :: BBox } 


                     
apply :: (BBox -> BBox) -> ViewPortBBox -> ViewPortBBox 
apply f (ViewPortBBox bbox1) = ViewPortBBox (f bbox1)
{-# INLINE apply #-}


data PageArrangement a where
  SingleArrangement:: PageOrigin -> PageDimension -> ViewPortBBox -> PageArrangement SinglePage 
  ContinuousSingleArrangement :: DesktopDimension -> ViewPortBBox -> PageArrangement ContinuousSinglePage



pageOrigin :: PageArrangement SinglePage :-> PageOrigin 
pageOrigin = lens getter setter
  where getter (SingleArrangement porig _ _) = porig
        setter porig (SingleArrangement _ pdim vbbox) = SingleArrangement porig pdim vbbox

pageDimension :: PageArrangement SinglePage :-> PageDimension
pageDimension = lens getter setter 
  where getter (SingleArrangement _ pdim _) = pdim
        setter pdim (SingleArrangement porig _ vbbox) = SingleArrangement porig pdim vbbox

viewPortBBox :: PageArrangement SinglePage :-> ViewPortBBox 
viewPortBBox = lens getter setter 
  where getter (SingleArrangement _ _ vbbox) = vbbox 
        setter vbbox (SingleArrangement porig pdim _) = SingleArrangement porig pdim vbbox 





