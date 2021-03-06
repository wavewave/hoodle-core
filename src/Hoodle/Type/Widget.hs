-----------------------------------------------------------------------------
-- |
-- Module      : Hoodle.Type.Widget
-- Copyright   : (c) 2013 Ian-Woo Kim
--
-- License     : BSD3
-- Maintainer  : Ian-Woo Kim <ianwookim@gmail.com>
-- Stability   : experimental
-- Portability : GHC
--
-- Types for Widgets 
-- 
-----------------------------------------------------------------------------

module Hoodle.Type.Widget 
( 
-- * types
  WidgetItem(..)
, CanvasWidgets      
, WidgetConfig
, LayerWidgetConfig 
, ClockWidgetConfig
-- * lenses 
, panZoomWidgetPosition
, panZoomWidgetTouchIsZoom
, panZoomWidgetConfig 
, layerWidgetConfig
, layerWidgetPosition
, layerWidgetShowContent
, clockWidgetConfig
, clockWidgetPosition
, clockWidgetTime
, widgetConfig 
, doesUsePanZoomWidget
, doesUseLayerWidget
, doesUseClockWidget
-- * defaults 
, defaultCanvasWidgets
, defaultLWConfig 
, defaultWidgetConfig
-- * utility
, allWidgets
) where

import Control.Lens (Simple,Lens,lens) 
-- 
import Hoodle.Type.PageArrangement 


-- | 
data WidgetItem = PanZoomWidget | LayerWidget | ClockWidget 
                deriving (Show,Eq,Ord)

-- | 
allWidgets :: [WidgetItem] 
allWidgets = [PanZoomWidget, LayerWidget, ClockWidget] 


-- | 
data PanZoomWidgetConfig = PZWConfig { _panZoomWidgetPosition :: CanvasCoordinate
                                     , _panZoomWidgetTouchIsZoom :: Bool  
                                     } 
                           
-- | 
panZoomWidgetPosition :: Simple Lens PanZoomWidgetConfig CanvasCoordinate
panZoomWidgetPosition = lens _panZoomWidgetPosition (\f a -> f { _panZoomWidgetPosition = a })

-- | 
panZoomWidgetTouchIsZoom :: Simple Lens PanZoomWidgetConfig Bool 
panZoomWidgetTouchIsZoom = lens _panZoomWidgetTouchIsZoom (\f a -> f { _panZoomWidgetTouchIsZoom = a})

-- |
data LayerWidgetConfig = LWConfig { _layerWidgetPosition :: CanvasCoordinate
                                  , _layerWidgetShowContent :: Bool
                                  }
-- | 
layerWidgetPosition :: Simple Lens LayerWidgetConfig CanvasCoordinate 
layerWidgetPosition = lens _layerWidgetPosition (\f a -> f { _layerWidgetPosition = a })
                         
-- | 
layerWidgetShowContent :: Simple Lens LayerWidgetConfig Bool
layerWidgetShowContent = lens _layerWidgetShowContent (\f a -> f { _layerWidgetShowContent = a})


-- |
data ClockWidgetConfig = ClkConfig { _clockWidgetPosition :: CanvasCoordinate
                                   , _clockWidgetTime :: (Int,Int,Int)
                                   }
     
                         
clockWidgetPosition :: Simple Lens ClockWidgetConfig CanvasCoordinate
clockWidgetPosition = lens _clockWidgetPosition (\f a -> f { _clockWidgetPosition = a } )

clockWidgetTime :: Simple Lens ClockWidgetConfig (Int,Int,Int)
clockWidgetTime = lens _clockWidgetTime (\f a -> f { _clockWidgetTime = a })


-- | 
data CanvasWidgets = 
  CanvasWidgets { _panZoomWidgetConfig :: PanZoomWidgetConfig
                , _layerWidgetConfig :: LayerWidgetConfig 
                , _clockWidgetConfig :: ClockWidgetConfig 
                , _widgetConfig :: WidgetConfig 
                }   

-- | 
panZoomWidgetConfig :: Simple Lens CanvasWidgets PanZoomWidgetConfig 
panZoomWidgetConfig = lens _panZoomWidgetConfig (\f a -> f { _panZoomWidgetConfig = a })

-- | 
layerWidgetConfig :: Simple Lens CanvasWidgets LayerWidgetConfig 
layerWidgetConfig = lens _layerWidgetConfig (\f a -> f { _layerWidgetConfig = a })

-- | 
clockWidgetConfig :: Simple Lens CanvasWidgets ClockWidgetConfig 
clockWidgetConfig = lens _clockWidgetConfig (\f a -> f { _clockWidgetConfig = a })


-- | default hoodle widgets
defaultCanvasWidgets :: CanvasWidgets
defaultCanvasWidgets = 
  CanvasWidgets
  { _panZoomWidgetConfig = defaultPZWConfig 
  , _layerWidgetConfig = defaultLWConfig 
  , _clockWidgetConfig = defaultClkConfig
  , _widgetConfig = defaultWidgetConfig 
  }   

-- | 
defaultPZWConfig :: PanZoomWidgetConfig 
defaultPZWConfig = 
  PZWConfig { _panZoomWidgetPosition = CvsCoord (100,100) 
            , _panZoomWidgetTouchIsZoom = False 
            } 
-- | 
defaultLWConfig :: LayerWidgetConfig 
defaultLWConfig = 
  LWConfig { _layerWidgetPosition = CvsCoord (100,300) 
           , _layerWidgetShowContent = False 
           }

-- | 
defaultClkConfig :: ClockWidgetConfig 
defaultClkConfig = 
  ClkConfig { _clockWidgetPosition = CvsCoord (500,300) 
            , _clockWidgetTime = (3,40,28)
            }


data WidgetConfig = WidgetConfig { _doesUsePanZoomWidget :: Bool 
                                 , _doesUseLayerWidget :: Bool 
                                 , _doesUseClockWidget :: Bool 
                                 } 

-- | flag for pan zoom widget 
doesUsePanZoomWidget :: Simple Lens WidgetConfig Bool 
doesUsePanZoomWidget = lens _doesUsePanZoomWidget (\f a -> f {_doesUsePanZoomWidget = a})

-- | flag for layer widget 
doesUseLayerWidget :: Simple Lens WidgetConfig Bool 
doesUseLayerWidget = lens _doesUseLayerWidget (\f a -> f {_doesUseLayerWidget = a}) 

-- | flag for clock widget 
doesUseClockWidget :: Simple Lens WidgetConfig Bool 
doesUseClockWidget = lens _doesUseClockWidget (\f a -> f {_doesUseClockWidget = a}) 


-- | default widget configuration 
defaultWidgetConfig :: WidgetConfig 
defaultWidgetConfig = WidgetConfig { _doesUsePanZoomWidget = False
                                   , _doesUseLayerWidget = False
                                   , _doesUseClockWidget = False
                                   } 


-- | widget config lens 
widgetConfig :: Simple Lens CanvasWidgets WidgetConfig
widgetConfig = lens _widgetConfig (\f a -> f { _widgetConfig =a } )
