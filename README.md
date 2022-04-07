# SeamCarving for iOS

## notes for usage

- replace `var frameFileName: String = "frame-1"` (line 127) with the file name of a frame within the Assets folder to select a specific frame
    - possible frameFileNames are:
        - "frame-1"
        - "frame-2"
        - "frame-4"
        - "frame-5"
        - "frame-6"
        - "frame-7"
        - "frame-8"
        
- currently only "frame-1" has cached seams in "precalculatedSeams.json" yet

- good example image to try on: https://upload.wikimedia.org/wikipedia/commons/4/47/VU-Banana-1000x1000.png
   - all example images that iOS provides are too large to fit into "frame-1"
   - if input image is too large to fit into the frame, there will be a logging message and the "start carving" and "select image" buttons won't get disabled

## further comments

- since the current png files of the frames have RGBA = (0,0,0,0) on every pixel with alpha = 0, i use two different frame representations:
  - "\<filename\>.png" for reading the alpha channel to retrieve the alphaMap
  - "\<filename\>-noalpha.png" for retrieving the original frame image without the mapped constraints on the alpha channel
  
- RGB for filler-constraint parts isn't clean (255,0,255) but differs between the given frames, therefor there is a global, constant dict which contains the RGB for each frame ((255,1,255) for frame 1, (255,41,255) for every other frame)
  
- precalculatedSeams.json is getting updated within the sandboxed iOS simulation environment, so once the the building folder gets cleaned, further calculated seams that were 
  not part of precalculatedSeams.json at building time will get lost on rebuild
  
- seam caching for carving only works correctly, if the cached seams have the same length as the current image height:
    - thus height carving rarely hits the cache, since the width of the image that was used for the seam caching after width carving would have to be the same as the width of the current image after width carving (i recognized that issue after the presentation)
    - no issues for caching in width carving

- there are issues with "frame-8", some parts of the frame have the same color as the constraint color (there might be other frames with that issue, i only tested "frame-1" and "frame-7" apart from 8. 1 and 7 are working as they should)
    - possible solution for future work might be to make the part-to-fill constraint also part of the alpha channel (with a different value than the not-to-carve constraint) instead of using the RGB channels to avoid those issues
