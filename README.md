# SeamCarving for iOS

## notes for usage

- replace `var frameFileName: String = "frame-1"` (line 127) with the file name of a frame within the Assets folder to select a specific frame


## further comments

- since the current png files of the frames have RGBA = (0,0,0,0) on every pixel with alpha = 0, i use two different frame representations:
  - "\<filename\>.png" for reading the alpha channel to retrieve the alphaMap
  - "\<filename\>-noalpha.png" for retrieving the original frame image without the mapped constraints on the alpha channel
  
- precalculatedSeams.json is getting updated within the sandboxed iOS simulation environment, so once the the building folder gets cleaned, further calculated seams that were 
  not part of precalculatedSeams.json at building time will get lost on rebuild
  
- seam caching for carving only works correctly, if the cached seams have the same length as the current image height:
    - thus height carving rarely hits the cache, since the width of the image that was used for the seam caching after width carving would have to be the same as the width of the current image after width carving (i recognized that issue after the presentation)
    - no issues for caching in width carving
