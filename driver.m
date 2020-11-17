 
clear, clc, close all
delete(instrfind)

%% GET User Inputs & Setup Options
SETUP_VIA_GUI = 0;
ANTENNA_TYPE = 1; %Hardcoded b/c only ISK/BOOST style currently supported.
if(SETUP_VIA_GUI)
    hApp = setup_tm();
    
else 
    % Manual/programmatic entry
    REAL_TIME_MODE = 1; %1 for from device 0 for playback from dat file
    ENABLE_RECORD = 0;
    datFile.path = '';
    datFile.name = 'tm_demo_log_110320_1620.dat';
    cfgFile.path = '';
    cfgFile.name = 'profile_2020_11_01T01_22_34_761.cfg';
    logFile.path = '';
    logFile.name = ['tm_demo_log_' datestr(now,'mmddyy_HHMM') '.dat'];
    offset.height = 2;
    offset.az = 0;
    offset.el = 0; %-20;
    comPort.cfg = 15;
    comPort.data = 14;
    comPort.status = 0;
end

offset.az = offset.az*-1; %flipping since transformations assume CCW is + direction

%% Set up file to record
if(ENABLE_RECORD && REAL_TIME_MODE)
    
    if(~isempty(logFile.path))
        % append slash if needed
        if(logFile.path(end)~='\' && logFile.path(end)~='/')
            logFile.path(end+1) = '\';
        end
        status = mkdir(logFile.path);
    else
        status = 1;
    end
    if(status)
        fid = fopen([logFile.path logFile.name],'w+');
    end
    if fid~= -1
        fprintf(['Opening ' logFile.name '. Ready to log data. \n']);
    else
        fprintf('Error with log file name or path. No logging. \n');
        ENABLE_RECORD = 0;
    end
else
    fid = -1;
    ENABLE_RECORD = 0;
end

%% SET and PARSE CFG FILE
try 
    [cliCfg] = readCfgFile([cfgFile.path cfgFile.name]);
catch ME
    fprintf('Error: Could not open CFG file. Quitting.');
    if(ENABLE_RECORD)
        fclose(fid);
    end
    return;
end

%Define supported CLI commands
sdkVersion = '03.03.00.01'; %TODO read this from device
demoType = 'TM';
[supported_cfgs] = defineCLICommands(sdkVersion,demoType);
    
%Parse CLI strings and calculate derived parameters
P = parseCLICommands2Struct(cliCfg, supported_cfgs);
calc_P = calculateChirpParams(P);


%% INIT SERIAL PORTS
if(REAL_TIME_MODE)
    %Init Ports
    hDataPort = initDataPort(comPort.data);
    hCfgPort = initCfgPort(comPort.cfg);
    
    %Check Port Status
    if(comPort.status == 0) %Unknown status
        if(hCfgPort ~= -1 && hDataPort ~=-1)
            if(hDataPort.BytesAvailable)
                %TODO: remove warning when config reload w/o NRST is enabled
                comPort.status = -1;
                fprintf('Device appears to already be running. Will not be able to load a new configuration. To load a new config, press NRST on the EVM and try again.');    
            else       
                fprintf(hCfgPort, 'version');
                pause(0.5); % adding some delay to make sure bytes are received
                response = '';
                if(hCfgPort.BytesAvailable)
                    for i=1:10 % version command reports back 10 lines TODO: change if SDK changes response
                        rstr = fgets(hCfgPort);
                        response = join(response, rstr);
                    end
                    fprintf('Test successful: CFG Port Opened & Data Received');
                    comPort.status = 1;
                else
                    fprintf('Port opened but no response received. Check port # and SOP mode on EVM');
                    comPort.status = -2;
                    fclose(hDataPort);
                    fclose(hCfgPort);
                end
            end
        else
            comPort.status = -2;
            fprintf('Could not open ports. Check port # and that EVM is powered with correct SOP mode.');    
        end
    end
     
else %REPLAY MODE
    
    %Load Data file
end

 %% Set flags based on COM port status
global RUN_VIZ
if(~REAL_TIME_MODE)
    RUN_VIZ = 1;
    LOAD_CFG = 0;
elseif(comPort.status == 1)
    LOAD_CFG = 1;
    RUN_VIZ = 1;
elseif(comPort.status == -1)
    LOAD_CFG = 0;
    RUN_VIZ = 1;
else
    RUN_VIZ = 0;
    LOAD_CFG = 0;
end
    
%% Load Config
if(LOAD_CFG) 
    loadCfg(hCfgPort, cliCfg);
end
        
if(RUN_VIZ)
%% INIT Figure
SHOW_PT_CLOUD = 1;
SHOW_TRACKED_OBJ = 1;
SHOW_STATS = 1;

% init plot axes
maxRange = max([calc_P.rangeMax_m]);

% init fov lines - approximate guidelines only
if (ANTENNA_TYPE==1)
    azFOV = 120; 
    elFOV = 40;  
else
    azFOV = 160; 
    elFOV = 160;
end

%% Pre-compute transformation matrix
rotMat_az = [cosd(offset.az) -sind(offset.az) 0; sind(offset.az) cosd(offset.az) 0; 0 0 1];
rotMat_el = [1 0 0; 0 cosd(offset.el) -sind(offset.el); 0 sind(offset.el) cosd(offset.el)];
transMat = rotMat_az*rotMat_el;

%% main - parse UART and update plots
if(REAL_TIME_MODE)
    bytesBuffer = zeros(1,hDataPort.InputBufferSize);
    bytesBufferLen = 0;
    isBufferFull = 0;
    READ_MODE = 'FIFO';
else
    % read in entire file 
    [bytesBuffer, bytesBufferLen, bytesAvailableFlag] = readDATFile2Buffer([datFile.path datFile.name], 'hex_dat');
    READ_MODE = 'ALL';
    [allFrames, bytesBuffer, bytesBufferLen, numFramesAvailable,validFrame] = parseBytes_OOB(bytesBuffer, bytesBufferLen, READ_MODE);
    hFrameSlider.Max = numFramesAvailable;
    hFrameSlider.Min = 0; %?
    hFrameSlider.SliderStep = [1 10].*1/(hFrameSlider.Max-hFrameSlider.Min);
end

mags = [];
frameIndex = 0;
HISTORY_LEN = 10;
curr_h_idx = 1;
history = cell(1, HISTORY_LEN);
history_is_full = 0;

N_SIN_FRAMES = 30;
doppler_t = N_SIN_FRAMES;
doppler_history = zeros(1, N_SIN_FRAMES);
dop_smooth = 0;
while (RUN_VIZ)    
    total_mag = 0;
    % get bytes from UART buffer or DATA file
    if(REAL_TIME_MODE)
        [bytesBuffer, bytesBufferLen, isBufferFull, bytesAvailableFlag] = readUARTtoBuffer(hDataPort, bytesBuffer, bytesBufferLen, ENABLE_RECORD, fid);
         % parse bytes to frame
        [newframe, bytesBuffer, bytesBufferLen, numFramesAvailable,validFrame] = parseBytes_OOB(bytesBuffer, bytesBufferLen, READ_MODE);
        frameIndex = 1;
    else
        frameIndex = frameIndex + 1;
        if (frameIndex > size(allFrames))
            break;
        end
        newframe = allFrames(frameIndex);
    end
    
   
    
    if(validFrame(frameIndex))
        statsString = {['Frame: ' num2str(newframe.header.frameNumber)], ['Num Frames in Buffer: ' num2str(numFramesAvailable)]}; %reinit stats string each new frame
        total_mag = total_mag + sum(newframe.detObj.doppler);
        if(1)

            % set frame flags
            HAVE_VALID_PT_CLOUD = ~isempty(newframe.detObj) && newframe.detObj.numDetectedObj ~= 0;
            HAVE_VALID_TARGET_LIST = ~isempty(newframe.targets);
            
            if(SHOW_PT_CLOUD)            
                if(HAVE_VALID_PT_CLOUD)
                    % Pt cloud hasn't been transformed based on offset TODO: move transformation to device
                    rotatedPtCloud = transMat * [newframe.detObj.x'; newframe.detObj.y'; newframe.detObj.z';];
                    rotatedPtCloud(3,:) = rotatedPtCloud(3,:)+offset.height;
                    rotatedPtCloud = rotatedPtCloud';
                    history{curr_h_idx} = rotatedPtCloud;
                    curr_h_idx = curr_h_idx + 1;
                    if (curr_h_idx > HISTORY_LEN)
                        curr_h_idx = curr_h_idx - HISTORY_LEN;
                        history_is_full = 1;
                    end
                    dop_poi = newframe.detObj.doppler(abs(newframe.detObj.doppler) > 0.1);
                    if ~isempty(dop_poi)
                        dop_smooth = 0.4*dop_smooth + 0.6*mean(dop_poi);
                    end
                    doppler_history = [doppler_history dop_smooth];
                    if length(doppler_history) > 200
                        doppler_history = doppler_history(end-N_SIN_FRAMES:end);
                        doppler_t = N_SIN_FRAMES;
                    else
                        doppler_t = doppler_t + 1;
                    end
                end
            end
            filteredPtCloud = filterStaticPoints(history, rotatedPtCloud);
%             disp(rotatedPtCloud(1,:));      

        end % have validFrame
    else % have data in newFrame
    end
    mags = [mags total_mag];
%     plot(mags);
    dopplerFrameStart = doppler_t - N_SIN_FRAMES + 1;
    plot(doppler_history(dopplerFrameStart:doppler_t));
    drawnow limitrate;
%     [curve, err] = sineFit(dopplerFrameStart:doppler_t, doppler_history(dopplerFrameStart:doppler_t));
    [f, err] = getFreq(doppler_history(dopplerFrameStart:doppler_t));
%     disp(['Frequency: ', num2str(f), ' err: ', num2str(err)]);
    if (err < 0.8 && f > 0.1)
        disp(['Frequency: ', num2str(f)]);
    end
    
%     if (err.rmse < 0.4*curve.A && curve.A > 0.07)
%         disp(['Frequency: ' num2str(curve.f ) ' error: ' num2str(err.rmse) ' A: ' num2str(curve.A)]);
%     end
    disp("Continuing...");
%     subplot(1,2,1);
%     tt = t-4:1/100:t;
%     plot(tt, sin(tt));
%     subplot(1,2,2);
%     plot((t-4:t), doppler_history(t-4:t));
%     drawnow limitrate;
%     pause on;
%     pause(0.05);
end %while inf


%% close ports
if(REAL_TIME_MODE)
    delete(instrfind);
    if(ENABLE_RECORD)
        c = fclose(fid);
        if(c == 0)
            disp('Log file closed w/o error.')
        else
            disp('Error closing log file.');
        end
    end
    disp('Visualizer terminated.')
end
end

%% Helper functions
function plotfig_closereq(src,callbackdata)
global RUN_VIZ
% Close request function 
% to display a question dialog box 
   s = questdlg('Close This Figure?',...
      'Close Request Function',...
      'Yes','No','Yes'); 
   switch s 
      case 'Yes'
         RUN_VIZ = 0; 
         delete(gcf)
      case 'No'
         RUN_VIZ = 1;
      return 
   end
end

function selection(selectView,ax)
    val = selectView.Value;
    switch val
        case 1
            view(ax, 0,90);           
        case 2
            view(ax, 90,0);
        case 3
            view(ax, 0,0);
        case 4
            view(ax, 170,10);
    end
end
