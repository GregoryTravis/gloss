{-# LANGUAGE BangPatterns, ScopedTypeVariables #-}
module Solver 
        ( mandelFrame
        , f2d
        , d2f)
where
import Graphics.Gloss.Data.Color
import Graphics.Gloss.Data.Picture
import Data.Word
import System.IO.Unsafe
import Unsafe.Coerce
import Debug.Trace
import Data.Bits
import GHC.Float
import Data.Array.Repa                          as R
import Data.Array.Repa.Repr.ForeignPtr          as R
import Data.Array.Repa.Algorithms.ColorRamp     as R
import Prelude                                  as P


mandelFrame 
        :: Int          -- Window Size X
        -> Int          -- Window Size Y
        -> Int          -- Zoom X
        -> Int          -- Zoom Y
        -> Double       -- Offset X
        -> Double       -- Offset Y
        -> Picture
mandelFrame winX winY zoomX zoomY offX offY
 = let  scaleX  :: Double = 1
        scaleY  :: Double = fromIntegral winY / fromIntegral winX
   in   makeFrame 
                winX winY
                zoomX zoomY
                (mandelPixel scaleX scaleY offX offY)
{-# NOINLINE mandelFrame #-}

-- Frame ----------------------------------------------------------------------
makeFrame 
        :: Int                  -- Window Size X
        -> Int                  -- Window Size Y
        -> Int                  -- Zoom X
        -> Int                  -- Zoom Y
        -> (Double -> Double -> Color) 
        -> Picture

makeFrame !winSizeX !winSizeY !zoomX !zoomY !makePixel
 = let  -- Size of the raw image to render.
        sizeX = winSizeX `div` zoomX
        sizeY = winSizeY `div` zoomY

        fsizeX, fsizeY  :: Double
        !fsizeX          = fromIntegral sizeX
        !fsizeY          = fromIntegral sizeY

        fsizeX2, fsizeY2 :: Double
        !fsizeX2        = fsizeX / 2
        !fsizeY2        = fsizeY / 2

        -- Midpoint of image.
        midX, midY :: Int
        !midX           = sizeX `div` 2
        !midY           = sizeY `div` 2

        {-# INLINE pixelOfIndex #-}
        pixelOfIndex (Z :. y :. x)
         = let  x'      = fromIntegral (x - midX) / fsizeX2
                y'      = fromIntegral (y - midY) / fsizeY2
           in   makePixel x' y'

        {-# INLINE conv #-} 
        conv (r, g, b)
         = let  r'      = fromIntegral r
                g'      = fromIntegral g
                b'      = fromIntegral b
                a       = 255 

                !w      =   unsafeShiftL r' 24
                        .|. unsafeShiftL g' 16
                        .|. unsafeShiftL b' 8
                        .|. a
           in   w

   in unsafePerformIO $ do

        -- Define the image, and extract out just the RGB color components.
        -- We don't need the alpha because we're only drawing one image.
        traceEventIO "Gloss.Raster[makeFrame]: start frame evaluation."
        (arrRGB :: Array F DIM2 Word32)
                <- R.computeP  
                        $ R.map conv
                        $ R.map unpackColor 
                        $ R.fromFunction (Z :. sizeY  :. sizeX)
                        $ pixelOfIndex
        traceEventIO "Gloss.Raster[makeFrame]: done, returning picture."

        -- Wrap the ForeignPtr from the Array as a gloss picture.
        let picture     
                = Scale (fromIntegral zoomX) (fromIntegral zoomY)
                $ bitmapOfForeignPtr
                        sizeX sizeY     -- raw image size
                        (R.toForeignPtr $ unsafeCoerce arrRGB)   
                                        -- the image data.
                        False           -- don't cache this in texture memory.

        return picture
{-# INLINE makeFrame #-}


-- Mandel ---------------------------------------------------------------------
mandelPixel 
        :: Double               -- Scale X
        -> Double               -- Scale Y
        -> Double               -- Offset X
        -> Double               -- Offset Y
        -> Double               -- X (Real)
        -> Double               -- Y (Imaginary)
        -> Color
mandelPixel scaleX scaleY x0 y0 x y
 = let  !cMax   = 100 :: Int
        !rMax   = 100 :: Double

        !x'     = (x0 + x) * scaleX
        !y'     = (y0 + y) * scaleY

        !count  = mandelRun (fromIntegral cMax) rMax x' y'
        !v      = fromIntegral count / fromIntegral cMax

        color'
         | v > 0.99     = rgb 0 0 0
         | (r, g, b)    <- rampColorHotToCold 0 1 v
         = rgb r g b
   in   color'
{-# INLINE mandelPixel #-}


mandelRun :: Int -> Double -> Double -> Double -> Int
mandelRun countMax rMax cr ci
 = go cr ci 0
 where
  go :: Double -> Double -> Int -> Int
  go !zr !zi  !count
   | count >= countMax                 = count
   | sqrt (zr * zr + zi * zi) > rMax   = count

   | otherwise                          
   = let !z2r     = zr*zr - zi*zi
         !z2i     = 2 * zr * zi
         !yr      = z2r + cr
         !yi      = z2i + ci
     in  go yr yi (count + 1)
{-# INLINE mandelRun #-}


-- Conversion -----------------------------------------------------------------
f2d :: Float -> Double
f2d = float2Double
{-# INLINE f2d #-}


d2f :: Double -> Float
d2f = double2Float
{-# INLINE d2f #-}


-- | Construct a color from red, green, blue components.
rgb  :: Float -> Float -> Float -> Color
rgb r g b   = makeColor' r g b 1.0
{-# INLINE rgb #-}


-- | Float to Word8 conversion because the one in the GHC libraries
--   doesn't have enout specialisations and goes via Integer.
word8OfFloat :: Float -> Word8
word8OfFloat f
        = fromIntegral (truncate f :: Int) 
{-# INLINE word8OfFloat #-}


unpackColor :: Color -> (Word8, Word8, Word8)
unpackColor c
        | (r, g, b, _) <- rgbaOfColor c
        = ( word8OfFloat (r * 255)
          , word8OfFloat (g * 255)
          , word8OfFloat (b * 255))
{-# INLINE unpackColor #-}

