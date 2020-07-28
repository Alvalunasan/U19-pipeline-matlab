%{
# across tif files, x-y shifts for motion registration
-> previousimaging.MotionCorrection
---
cross_files_x_shifts           : blob      # nFrames x 2, meta file, fileMCorr-xShifts
cross_files_y_shifts           : blob      # nFrames x 2, meta file, fileMCorr-yShifts
cross_files_reference_image    : longblob  # 512 x 512, meta file, fileMCorr-reference
%}


classdef MotionCorrectionAcrossFiles < dj.Part
    properties(SetAccess=protected)
        master   = previousimaging.MotionCorrection
    end
    % ingested by previousimaging.MotionCorrection
end