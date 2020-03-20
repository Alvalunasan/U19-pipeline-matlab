%{
% table that reflects the contents in the file recInfo.mat
-> meso.Scan
---
file_name_base    : varchar(255)  # base name of the file ("FileName")
scan_width        : int           # width of scanning in pixels ("Width")
scan_height       : int           # height of scanning in pixels ("Height")
acq_time          : datetime      # acquisition time ("AcqTime")
n_depths          : tinyint       # number of depths ("nDepths")
scan_depths       : tinyint       # depths in this scan ("Zs")
frame_rate        : float         # ("frameRate")
inter_fov_lag_sec : float         # time lag in secs between fovs ("interROIlag_sec")
frame_ts_sec      : longblob      # frame timestamps in secs 1xnFrames ("Timing.Frame_ts_sec")
power_percent     : float         # percentage of power used in this scan ("Scope.Power_percent")
channels          : blob          # ----is this the channer number or total number of channels? ("Scope.Channels")
cfg_filename      : varchar(255)  # cfg file path ("Scope.cfgFilename")
usr_filename      : varchar(255)  # usr file path ("Scope.usrFilename")
fast_z_lag        : float         # fast z lag ("Scope.fastZ_lag")
fast_z_flyback_time: float        # ("Scope.fastZ_flybackTime")
line_period       : float         # scan time per line ("Scope.linePeriod")
scan_frame_period : float         # ("Scope.scanFramePeriod")
scan_volume_rate  : float         # ("Scope.scanVolumeRate")
flyback_time_per_frame: float     # ("Scope.flybackTimePerFrame")
flyto_time_per_scan_field: float  # ("Scope.flytoTimePerScanfield")
fov_corner_points : blob          # coordinates of the corners of the full 5mm FOV, in microns ("Scope.fovCornerPoints")
nfovs             : int           # number of field of view
nframes           : int           # number of frames in the scan
nframes_good      : int           # number of frames in the scan before acceptable sample bleaching threshold is crossed
%}


classdef ScanInfo < dj.Imported
  
  methods(Access=protected)
    
    function makeTuples(self, key)
      % ingestion triggered by the existence of Scan
      % will run a modified version of mesoscopeSetPreproc
      
      curr_dir       = pwd; 
      scan_directory = fetch1(key,'scan_directory');
      cd(scan_directory)
      
      fprintf('------------ preparing %s --------------\n',scan_directory)
      mkdir('originalStacks');
      
      %% loop through files to read all image headers
      
      % get header with parfor loop
      fprintf('\tgetting headers...\n')
      
      fl      = dir('*tif'); % tif file list
      poolobj = parpool;
      
      parfor iF = 1:numel(fl)
        [imheader{iF},parsedInfo{iF}] = parseMesoscopeTifHeader(fl{iF});
      end
      
      % get recording info from headers
      fprintf('\tsaving recInfo...\n')
      framesPerFile = zeros(numel(fl),1);
      for iF = 1:numel(fl)
        if iF == 1
          recInfo = parsedInfo{iF};
        else
          if parsedInfo{iF}.Timing.Frame_ts_sec(1) == 0
            parsedInfo{iF}.Timing.Frame_ts_sec = parsedInfo{iF}.Timing.Frame_ts_sec + recInfo.Timing.Frame_ts_sec(end) + 1/recInfo.frameRate;
          end
          recInfo.Timing.Frame_ts_sec = [recInfo.Timing.Frame_ts_sec; parsedInfo{iF}.Timing.Frame_ts_sec];
          recInfo.Timing.BehavFrames  = [recInfo.Timing.BehavFrames;  parsedInfo{iF}.Timing.BehavFrames];
        end
        framesPerFile(iF) = numel(imheader{iF});
      end
      recInfo.nFrames     = numel(recInfo.Timing.Frame_ts_sec);
      
      %% find out last good frame based on bleaching
      lastGoodFrame       = selectFramesFromMeanF(scan_directory);
      cumulativeFrames    = cumsum(framesPerFile);
      lastGoodFile        = find(cumulativeFrames >= lastGoodFrame,1,'first');
      lastFrameInFile     = lastGoodFrame - cumulativeFrames(max([1 lastGoodFile-1]));
      
      %% write to this table
      key.file_name_base            = recInfo.FileName;
      key.scan_width                = recInfo.Width;
      key.scan_height               = recInfo.Height;
      key.acq_time                  = recInfo.AcqTime;
      key.n_depths                  = recInfo.nDepths;
      key.scan_depths               = recInfo.Zs;
      key.frame_rate                = recInfo.frameRate;
      key.inter_fov_lag_sec         = recInfo.interROIlag_sec;
      key.frame_ts_sec              = recInfo.Timing.Frame_ts_sec;
      key.power_percent             = recInfo.Scope.Power_percent;
      key.channels                  = recInfo.Scope.Channels;
      key.cfg_filename              = recInfo.Scope.cfgFilename;
      key.usr_filename              = recInfo.Scope.usrFilename;
      key.fast_z_lag                = recInfo.Scope.fastZ_lag;
      key.fast_z_flyback_time       = recInfo.Scope.fastZ_flybackTime;
      key.line_period               = recInfo.Scope.linePeriod;
      key.scan_frame_period         = recInfo.Scope.scanFramePeriod;
      key.scan_volume_rate          = recInfo.Scope.scanVolumeRate;
      key.flyback_time_per_frame    = recInfo.Scope.flybackTimePerFrame;
      key.flyto_time_per_scan_field = recInfo.Scope.flytoTimePerScanfield;
      key.fov_corner_points         = recInfo.Scope.fovCornerPoints;
      key.nfovs                     = sum(cell2mat(cellfun(@(x)(numel(x)),{recInfo.ROI(:).Zs},'uniformoutput',false)));
      key.nframes                   = recInfo.nFrames;
      key.nframes_good              = lastGoodFrame;
      
      self.insert(key)
      
      %% scan image concatenates FOVs (ROIs) by adding rows, with padding between them.
      % This part parses and write tifs individually for each FOV 
            
      fieldLs = {'ImageLength','ImageWidth','BitsPerSample','Compression', ...
        'SamplesPerPixel','PlanarConfiguration','Photometric'};
      fprintf('\tparsing ROIs...\n')
      
      nROI        = recInfo.nROIs;
      ROInr       = arrayfun(@(x)(x.pixelResolutionXY(2)),recInfo.ROI);
      ROInc       = arrayfun(@(x)(x.pixelResolutionXY(1)),recInfo.ROI);
      interROIlag = recInfo.interROIlag_sec;
      Depths      = recInfo.nDepths;
      
      % make the folders in advance, before the parfor loop
      for iROI = 1:nROI
        for iDepth = 1:Depths
          mkdir(sprintf('ROI%02d_z%d',iROI,iDepth));
        end
      end
      
      parfor iF = 1:numel(fl)
        fprintf('%s\n',fl{iF})
        
        % read image and header
        if iF <= lastGoodFile % do not write frames beyond last good frame based on bleaching
          readObj    = Tiff(fl{iF},'r');
          thisstack  = zeros(imheader{iF}(1).Height,imheader{iF}(1).Width,numel(imheader{iF}),'uint16');
          for iFrame = 1:numel(imheader{iF})
            readObj.setDirectory(iFrame);
            thisstack(:,:,iFrame) = readObj.read();
          end
          
          % number of ROIs and blank pixels from beam travel
          [nr,nc,~]  = size(thisstack);
          padsize    = (nr - sum(ROInr)) / (nROI - 1);
          rowct      = 1;
          
          % create a separate tif for each ROI
          for iROI = 1:nROI
            
            thislag  = interROIlag*(iROI-1);
            
            for iDepth = 1:Depths
              
              % extract correct frames
              zIdx       = iDepth:Depths:size(thisstack,3);
              substack   = thisstack(rowct:rowct+ROInr(iROI)-1,1:ROInc(iROI),zIdx); % this square ROI, depths are interleaved
              thisfn     = sprintf('./ROI%02d_z%d/%sROI%02d_z%d_%s',iROI,iDepth,basename,iROI,iDepth,fl{iF}(stridx+1:end));
              writeObj   = Tiff(thisfn,'w');
              thisheader = struct([]);
              
              % set-up header
              for iField = 1:numel(fieldLs)
                switch fieldLs{iField}
                  case 'TIFF File'
                    thisheader(1).(fieldLs{iField}) = thisfn;
                    
                  case 'ImageLength'
                    thisheader(1).(fieldLs{iField}) = nc;
                    
                  otherwise
                    thisheader(1).(fieldLs{iField}) = readObj.getTag(fieldLs{iField});
                end
              end
              thisheader(1).ImageDescription        = imheader{iF}(zIdx(1)).ImageDescription;
              
              % write first frame
              writeObj.setTag(thisheader);
              writeObj.setTag('SampleFormat',Tiff.SampleFormat.UInt);
              writeObj.write(substack(:,:,1));
              
              % write frames
              for iZ = 2:size(substack,3)
                % do not write frames beyond last good frame based on bleaching
                if iF == lastGoodFile && iZ > lastFrameInFile; continue; end
                
                % account for ROI lags in new time stamps
                imdescription = imheader{iF}(zIdx(iZ)).ImageDescription;
                old           = cell2mat(regexp(cell2mat(regexp(imdescription,'frameTimestamps_sec = [0-9]+.[0-9]+','match')),'\d+.\d+','match'));
                new           = num2str(thislag + str2double(old));
                imdescription = replace(imdescription,old,new);
                
                % write image and hedaer
                thisheader(1).ImageDescription = imdescription;
                writeObj.writeDirectory();
                writeObj.setTag(thisheader);
                writeObj.setTag('SampleFormat',Tiff.SampleFormat.UInt);
                write(writeObj,substack(:,:,iZ));
              end
              
              % close tif stack object
              writeObj.close();
              
              %clear substack
            end
            
            % update first row index
            rowct    = rowct+padsize+ROInr(iROI);
          end
          
          %MDia: close all Tiff objects otherwise can't move files (at least on windows)
          readObj.close();
        end
        
        % now move file
        movefile(fl{iF},sprintf('originalStacks/%s',fl{iF}));
      end
      
      %% write to FieldOfView table
      ct = 1;
      for iROI = 1:nROI
        ndepths = numel(recInfo.ROI(iROI).Zs);
        for iZ = 1:ndepths
          fov_key           = [];
          fov_key.fov       = ct;
          fov_key.directory = sprintf('%s/ROI%02d_z%d',scan_directory,iROI,iZ);
          
          if ~isempty(recInfo.ROI(iROI).name)
            thisname        = sprintf('%s_z%d',recInfo.ROI(iROI).name,iZ);
          else
            thisname        = sprintf('ROI%02d_z%d',iROI,iZ);
          end
          
          fov_key.fov_name             = thisname;
          fov_key.depth                = recInfo.ROI(iROI).Zs(iZ);
          fov_key.fov_center_xy        = recInfo.ROI(iROI).centerXY;
          fov_key.fov_rotation_degrees = recInfo.ROI(iROI).sizeXY;
          
          ct = ct+1;
          makeTuples(meso.FieldOfView,fov_key)
        end
      end
      
      
%       fov                     :  tinyint        # number of the field of view in this scan 
% ---
% fov_directory           :  varchar(255)   # the absolute directory created for this fov
% fov_name=null           :  varchar(32)    # name of the field of view ("name")
% fov_depth               :  float          # depth of the field of view ("Zs") should be a number or a vector? 
% fov_center_xy           :  blob           # X-Y coordinate for the center of the FOV in microns. One for each FOV in scan ("centerXY")
% fov_size_xy             :  blob           # X-Y size of the FOV in microns. One for each FOV in scan (sizeXY)
% fov_rotation_degrees    :  float          # rotation of the FOV with respect to cardinal axes in degrees. One for each FOV in scan ("rotationDegrees")
% fov_pixel_resolution_xy :  float          # number of pixels for rows and columns of the FOV. One for each FOV in scan ("")n
% fov_discrete_plane_mode :  boolean   
      %% wrap up
      delete(poolobj)
      cd(curr_dir)
      fprintf('\tdone after %1.1f min\n',toc/60)
      
    end
  end
end

