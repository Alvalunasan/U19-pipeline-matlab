%{
% field of view information, from the original recInfo.ROI
-> meso.Scan
fov                     :  tinyint        # number of the field of view in this scan 
---
fov_directory           :  varchar(255)   # the absolute directory created for this fov
fov_name=null           :  varchar(32)    # name of the field of view ("name")
fov_depth               :  float          # depth of the field of view ("Zs") should be a number or a vector? 
fov_center_xy           :  blob           # X-Y coordinate for the center of the FOV in microns. One for each FOV in scan ("centerXY")
fov_size_xy             :  blob           # X-Y size of the FOV in microns. One for each FOV in scan (sizeXY)
fov_rotation_degrees    :  float          # rotation of the FOV with respect to cardinal axes in degrees. One for each FOV in scan ("rotationDegrees")
fov_pixel_resolution_xy :  float          # number of pixels for rows and columns of the FOV. One for each FOV in scan ("")n
fov_discrete_plane_mode :  boolean        # true if FOV is only defined (acquired) at a single specifed depth in the volume. One for each FOV in scan ("discretePlaneMode") should this be boolean?
%}

classdef FieldOfView < dj.Imported
    % ingestion handled by ScanInfo
    methods(Access=protected)
        function makeTuples(self, key)
            
            % load the original tiff, parse that, fill in these
            % information, generate new tiff files, insert the new names
            % into the table FieldOfViewFile
          
            self.insert(key)
            
            insert(meso.FieldOfViewFile, file_entries)
                % ingestion triggered by the existence of Scan
                % will run a modified version of mesoscopeSetPreproc
                % will also trigger the ingestion into the table FieldOfView
        end
    end
end