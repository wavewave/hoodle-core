module Application.HXournal.Draw where

import Graphics.UI.Gtk hiding (get)
import Graphics.Xournal.Render 
import Graphics.Rendering.Cairo

import Control.Applicative 
import Control.Category
import Data.Label
import Prelude hiding ((.),id)

import Text.Xournal.Type

import Graphics.Xournal.Render.BBox 
import Application.HXournal.Type 
import Application.HXournal.Device

data CanvasPageGeometry = 
  CanvasPageGeometry { screen_size :: (Double,Double) 
                     , canvas_size :: (Double,Double)
                     , page_size :: (Double,Double)
                     , canvas_origin :: (Double,Double) 
                     , page_origin :: (Double,Double)
                     }
  deriving (Show)  

getCanvasPageGeometry :: IPage a => 
                         DrawingArea 
                         -> a 
                         -> (Double,Double) 
                         -> IO CanvasPageGeometry
getCanvasPageGeometry canvas page (xorig,yorig) = do 
  win <- widgetGetDrawWindow canvas
  (w',h') <- widgetGetSize canvas
  screen <- widgetGetScreen canvas
  (ws,hs) <- (,) <$> screenGetWidth screen <*> screenGetHeight screen
  let (Dim w h) = pageDim page
  (x0,y0) <- drawWindowGetOrigin win
  return $ CanvasPageGeometry (fromIntegral ws, fromIntegral hs) 
                              (fromIntegral w', fromIntegral h') 
                              (w,h) 
                              (fromIntegral x0,fromIntegral y0)
                              (xorig, yorig)

core2pageCoord :: CanvasPageGeometry -> ZoomMode 
                  -> (Double,Double) -> (Double,Double)
core2pageCoord cpg zmode (px,py) = 
  let s =  1.0 / getRatioFromPageToCanvas cpg zmode 
  in (px * s, py * s)
  
wacom2pageCoord :: CanvasPageGeometry 
                   -> ZoomMode 
                   -> (Double,Double) 
                   -> (Double,Double)
wacom2pageCoord cpg@(CanvasPageGeometry (ws,hs) (_w',_h') (_w,_h) (x0,y0) (xorig,yorig)) 
                zmode 
                (px,py) 
  = let (x1,y1) = (ws*px-x0,hs*py-y0)
        s = 1.0 / getRatioFromPageToCanvas cpg zmode
        (xo,yo) = case zmode of
                    Original -> (xorig,yorig)
                    FitWidth -> (0,yorig)
                    _ -> error "not implemented wacom2pageCoord"
    in  (x1*s+xo,y1*s+yo)

device2pageCoord :: CanvasPageGeometry 
                 -> ZoomMode 
                 -> PointerCoord  
                 -> (Double,Double)
device2pageCoord cpg zmode pcoord@(PointerCoord _ _ _)  = 
 let (px,py) = (,) <$> pointerX <*> pointerY $ pcoord  
 in case pointerType pcoord of 
      Core -> core2pageCoord  cpg zmode (px,py)
      _    -> wacom2pageCoord cpg zmode (px,py)
device2pageCoord _ _ NoPointerCoord = (-100,-100)


transformForPageCoord :: CanvasPageGeometry -> ZoomMode -> Render ()
transformForPageCoord cpg zmode = do 
  let (xo,yo) = page_origin cpg
  let s = getRatioFromPageToCanvas cpg zmode  
  scale s s
  translate (-xo) (-yo)      
  
updateCanvas :: DrawingArea -> XournalBBox -> Int -> ViewInfo -> IO ()
updateCanvas canvas xoj pagenum vinfo = do 
  let zmode  = get zoomMode vinfo
      origin = get viewPortOrigin vinfo
  let currpage = ((!!pagenum).xournalPages) xoj
  geometry <- getCanvasPageGeometry canvas currpage origin
  win <- widgetGetDrawWindow canvas
  renderWithDrawable win $ do
    transformForPageCoord geometry zmode
    cairoDrawPage currpage
  return ()

updateCanvasBBoxOnly :: DrawingArea -> XournalBBox -> Int -> ViewInfo -> IO ()
updateCanvasBBoxOnly canvas xoj pagenum vinfo = do 
  let zmode  = get zoomMode vinfo
      origin = get viewPortOrigin vinfo
  let currpage = ((!!pagenum).xournalPages) xoj
  geometry <- getCanvasPageGeometry canvas currpage origin
  win <- widgetGetDrawWindow canvas
  renderWithDrawable win $ do
    transformForPageCoord geometry zmode
    cairoDrawPageBBoxOnly currpage
  return ()


drawBBox :: DrawingArea -> PageBBox -> ViewInfo -> BBox -> IO ()
drawBBox canvas page vinfo bbox = do 
  let zmode  = get zoomMode vinfo
      origin = get viewPortOrigin vinfo
  geometry <- getCanvasPageGeometry canvas page origin
  win <- widgetGetDrawWindow canvas
  renderWithDrawable win $ do
    setLineWidth 0.5 
    setSourceRGBA 1.0 0.0 0.0 1.0
    transformForPageCoord geometry zmode
    let (x1,y1) = bbox_upperleft bbox
        (x2,y2) = bbox_lowerright bbox
    rectangle x1 y1 (x2-x1) (y2-y1)
    stroke
    --fill
  return ()


getRatioFromPageToCanvas :: CanvasPageGeometry -> ZoomMode -> Double 
getRatioFromPageToCanvas _cpg Original = 1.0 
getRatioFromPageToCanvas cpg FitWidth = 
  let (w,_)  = page_size cpg 
      (w',_) = canvas_size cpg 
  in  w'/w
getRatioFromPageToCanvas _cpg (Zoom s) = s 

drawSegment :: DrawingArea
               -> CanvasPageGeometry 
               -> ZoomMode 
               -> Double 
               -> (Double,Double,Double,Double) 
               -> (Double,Double) 
               -> (Double,Double) 
               -> IO () 
drawSegment canvas cpg zmode wdth (r,g,b,a) (x0,y0) (x,y) = do 
  win <- widgetGetDrawWindow canvas
  renderWithDrawable win $ do
    transformForPageCoord cpg zmode
    setSourceRGBA r g b a
    setLineWidth wdth
    moveTo x0 y0
    lineTo x y
    stroke
  
showXournalBBox :: DrawingArea -> XournalBBox -> Int -> ViewInfo -> IO ()
showXournalBBox canvas xojbbox pagenum vinfo = do 
  let zmode  = get zoomMode vinfo
      origin = get viewPortOrigin vinfo
  let currpagebbox = ((!!pagenum).xojbbox_pages) xojbbox
      currpage = pageFromPageBBox currpagebbox
      strs = do 
        l <- pagebbox_layers currpagebbox 
        s <- layerbbox_strokes l
        return s 
  geometry <- getCanvasPageGeometry canvas currpage origin
  win <- widgetGetDrawWindow canvas
  renderWithDrawable win $ do
    transformForPageCoord geometry zmode
    setSourceRGBA 1.0 0 0 1.0 
    setLineWidth  0.5 
    let f str = do 
          let BBox (ulx,uly) (lrx,lry) = strokebbox_bbox str 
          rectangle ulx uly (lrx-ulx) (lry-uly)
          stroke 
    mapM_ f strs 
  return ()

showBBox :: DrawingArea -> CanvasPageGeometry -> ZoomMode -> BBox -> IO ()
showBBox canvas cpg zmode (BBox (ulx,uly) (lrx,lry)) = do 
  win <- widgetGetDrawWindow canvas
  renderWithDrawable win $ do
    transformForPageCoord cpg zmode
    setSourceRGBA 0.0 1.0 0.0 1.0 
    setLineWidth  1.0 
    rectangle ulx uly (lrx-ulx) (lry-uly)    
    stroke
  return ()
