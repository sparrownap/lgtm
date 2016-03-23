%%
% The MIT License (MIT)
% Copyright (c) 2016 Ethan Gaebel <egaebel@vt.edu>
% 
% Permission is hereby granted, free of charge, to any person obtaining a 
% copy of this software and associated documentation files (the "Software"), 
% to deal in the Software without restriction, including without limitation 
% the rights to use, copy, modify, merge, publish, distribute, sublicense, 
% and/or sell copies of the Software, and to permit persons to whom the 
% Software is furnished to do so, subject to the following conditions:
% 
% The above copyright notice and this permission notice shall be included 
% in all copies or substantial portions of the Software.
% 
% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS 
% OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING 
% FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER 
% DEALINGS IN THE SOFTWARE.
%

function spotfi
    %% DEBUG AND OUTPUT VARIABLES-----------------------------------------------------------------%%
    globals_init()
    global DEBUG_BRIDGE_CODE_CALLING
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Get the full path to the currently executing file and change the
    % pwd to the folder this file is contained in...
    [current_directory, ~, ~] = fileparts(mfilename('fullpath'));
    cd(current_directory);
    % Paths for the csitool functions provided
    path('../../linux-80211n-csitool-supplementary/matlab', path);
	%path('../../../linux-80211n-csitool-supplementary/matlab/sample_data', path);
    if DEBUG_BRIDGE_CODE_CALLING
        fprintf('The path: %s\n', path)
        fprintf('The pwd: %s\n', pwd)
    end
    if ~DEBUG_BRIDGE_CODE_CALLING
        close all
        clc
    end
    % data_files = {'test-data/line-of-sight-localization-tests--in-room/los-test-heater.dat'};
    % top_aoas = run(data_files);
    % top_aoas
    data_file = {'../injection-monitor/.lgtm-monitor.dat'};
    %data_file = {'test-data/line-of-sight-localization-tests--in-room/los-test-heater.dat'};
    top_aoas = run(data_file);
    output_file_name = '../injection-monitor/.lgtm-top-aoas';
    output_top_aoas(top_aoas, output_file_name);
    if DEBUG_BRIDGE_CODE_CALLING
        fprintf('Done Running!\n')
    end
end

%% Output the array of top_aoas to the given file as doubles
% top_aoas         -- The angle of arrivals selected as the most likely.
% output_file_name -- The name of the file to write the angle of arrivals to.
function output_top_aoas(top_aoas, output_file_name)
    output_file = fopen(output_file_name, 'wb');
    if (output_file < 0)
        error('Couldn''t open file %s', output_file_name);
    end
    top_aoas
    for ii = 1:size(top_aoas, 1)
        fprintf(output_file, '%g ', top_aoas(ii, 1));
    end
    fprintf(output_file, '\n');
    fclose(output_file);
end

function globals_init
    %% DEBUG AND OUTPUT VARIABLES-----------------------------------------------------------------%%
    % Debug Controls
    global DEBUG_PATHS
    global DEBUG_PATHS_LIGHT
    global NUMBER_OF_PACKETS_TO_CONSIDER
    global DEBUG_GMM
    global DEBUG_BRIDGE_CODE_CALLING
    DEBUG_PATHS = false;
    DEBUG_PATHS_LIGHT = false;
    %% TODO: Tune this for prod
    NUMBER_OF_PACKETS_TO_CONSIDER = 100; % Set to -1 to ignore this variable's value
    DEBUG_GMM = false;
    DEBUG_BRIDGE_CODE_CALLING = false;
    
    % Output controls
    global OUTPUT_AOAS
    global OUTPUT_TOFS
    global OUTPUT_AOA_MUSIC_PEAK_GRAPH
    global OUTPUT_TOF_MUSIC_PEAK_GRAPH
    global OUTPUT_AOA_TOF_MUSIC_PEAK_GRAPH
    global OUTPUT_SELECTIVE_AOA_TOF_MUSIC_PEAK_GRAPH
    global OUTPUT_AOA_VS_TOF_PLOT
    global OUTPUT_SUPPRESSED
    global OUTPUT_PACKET_PROGRESS
    global OUTPUT_FIGURES_SUPPRESSED
    OUTPUT_AOAS = false;
    OUTPUT_TOFS = false;
    OUTPUT_AOA_MUSIC_PEAK_GRAPH = false;%true;
    OUTPUT_TOF_MUSIC_PEAK_GRAPH = false;%true;
    OUTPUT_AOA_TOF_MUSIC_PEAK_GRAPH = false;
    OUTPUT_SELECTIVE_AOA_TOF_MUSIC_PEAK_GRAPH = false;
    OUTPUT_AOA_VS_TOF_PLOT = false;
    OUTPUT_SUPPRESSED = true;
    OUTPUT_PACKET_PROGRESS = false;
    OUTPUT_FIGURES_SUPPRESSED = false; % Set to true when running in deployment from command line
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
end

%% Runs the SpotFi test over the passed in data files which each contain CSI data for many packets
% data_files -- a cell array of file paths to data files
function output_top_aoas = run(data_files)
    %% DEBUG AND OUTPUT VARIABLES-----------------------------------------------------------------%%
    % Debug Controls
    global NUMBER_OF_PACKETS_TO_CONSIDER
    
    % Output controls
    global OUTPUT_SUPPRESSED
    global OUTPUT_AOA_VS_TOF_PLOT
    global OUTPUT_PACKET_PROGRESS
    global OUTPUT_FIGURES_SUPPRESSED
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    % Set physical layer parameters (frequency, subfrequency spacing, and antenna spacing
    antenna_distance = 0.1;
    % frequency = 5 * 10^9;
    % frequency = 5.785 * 10^9;
    frequency = 5.32 * 10^9;
    sub_freq_delta = (40 * 10^6) / 30;
    
    % Loop over passed in data files
    for data_file_index = 1:length(data_files)
        % Read data file in
        if ~OUTPUT_SUPPRESSED
            fprintf('\n\nRunning on data file: %s\n', data_files{data_file_index})
        end
        csi_trace = read_bf_file(data_files{data_file_index});
        
        % Extract CSI information for each packet
        if ~OUTPUT_SUPPRESSED
            fprintf('Have CSI for %d packets\n', length(csi_trace))
        end
        
        % Set the number of packets to consider, by default consider all
        num_packets = length(csi_trace);
        if NUMBER_OF_PACKETS_TO_CONSIDER ~= -1
            num_packets = NUMBER_OF_PACKETS_TO_CONSIDER;
        end
        if ~OUTPUT_SUPPRESSED
            fprintf('Considering CSI for %d packets\n', num_packets)
        end
        
        % Loop over packets, estimate AoA and ToF from the CSI data for each packet
        aoa_packet_data = cell(num_packets, 1);
        tof_packet_data = cell(num_packets, 1);
        packet_one_phase_matrix = 0;
        
        
        % Do computations for packet one so the packet loop can be parallelized
        % Get CSI for current packet
        csi_entry = csi_trace{1};
        csi = get_scaled_csi(csi_entry);
        % Only consider measurements for transmitting on one antenna
        csi = csi(1, :, :);
        % Remove the single element dimension
        csi = squeeze(csi);

        % Sanitize ToFs with Algorithm 1
        packet_one_phase_matrix = unwrap(angle(csi), pi, 2);
        sanitized_csi = spotfi_algorithm_1(csi, sub_freq_delta);
        % Acquire smoothed CSI matrix
        smoothed_sanitized_csi = smooth_csi(sanitized_csi);
        % Run SpotFi's AoA-ToF MUSIC algorithm on the smoothed and sanitized CSI matrix
        [aoa_packet_data{1}, tof_packet_data{1}] = aoa_tof_music(...
                smoothed_sanitized_csi, antenna_distance, frequency, sub_freq_delta, ...
                data_files{data_file_index});
        
        %% TODO: REMEMBER THIS IS A PARFOR LOOP, AND YOU CHANGED THE ABOVE CODE AND THE BEGIN INDEX
        parfor (packet_index = 2:num_packets, 3)
            if ~OUTPUT_SUPPRESSED && OUTPUT_PACKET_PROGRESS
                fprintf('Packet %d of %d\n', packet_index, num_packets)
            end
            % Get CSI for current packet
            csi_entry = csi_trace{packet_index};
            csi = get_scaled_csi(csi_entry);
            % Only consider measurements for transmitting on one antenna
            csi = csi(1, :, :);
            % Remove the single element dimension
            csi = squeeze(csi);

            % Sanitize ToFs with Algorithm 1
            %% TODO: this is commented out for parfor's sake
            %{
            if packet_index == 1
                packet_one_phase_matrix = unwrap(angle(csi), pi, 2);
                sanitized_csi = spotfi_algorithm_1(csi, sub_freq_delta);
            else
                sanitized_csi = spotfi_algorithm_1(csi, sub_freq_delta, packet_one_phase_matrix);
            end
            %}
            sanitized_csi = spotfi_algorithm_1(csi, sub_freq_delta, packet_one_phase_matrix);
            
            % Acquire smoothed CSI matrix
            smoothed_sanitized_csi = smooth_csi(sanitized_csi);
            % Run SpotFi's AoA-ToF MUSIC algorithm on the smoothed and sanitized CSI matrix
            [aoa_packet_data{packet_index}, tof_packet_data{packet_index}] = aoa_tof_music(...
                    smoothed_sanitized_csi, antenna_distance, frequency, sub_freq_delta, ...
                    data_files{data_file_index});
        end
        
        % Find the number of elements that will be in the full_measurement_matrix
        % The value must be computed since each AoA may have a different number of ToF peaks
        full_measurement_matrix_size = 0;
        % Packet Loop
        for packet_index = 1:num_packets
            tof_matrix = tof_packet_data{packet_index};
            aoa_matrix = aoa_packet_data{packet_index};
            % AoA Loop
            for j = 1:size(aoa_matrix, 1)
                % ToF Loop
                for k = 1:size(tof_matrix(j, :), 2)
                    % Break once padding is hit
                    if tof_matrix(j, k) < 0
                        break
                    end
                    full_measurement_matrix_size = full_measurement_matrix_size + 1;
                end
            end
        end
        
        if ~OUTPUT_SUPPRESSED
            fprintf('Full Measurement Matrix Size: %d\n', full_measurement_matrix_size)
        end
        
        % Construct the full measurement matrix
        full_measurement_matrix = zeros(full_measurement_matrix_size, 2);
        full_measurement_matrix_index = 1;
        % Packet Loop
        for packet_index = 1:num_packets
            tof_matrix = tof_packet_data{packet_index};
            aoa_matrix = aoa_packet_data{packet_index};
            % AoA Loop
            for j = 1:size(aoa_matrix, 1)
                % ToF Loop
                for k = 1:size(tof_matrix(j, :), 2)
                    % Break once padding is hit
                    if tof_matrix(j, k) < 0
                        break
                    end
                    full_measurement_matrix(full_measurement_matrix_index, 1) = aoa_matrix(j, 1);
                    full_measurement_matrix(full_measurement_matrix_index, 2) = tof_matrix(j, k);
                    full_measurement_matrix_index = full_measurement_matrix_index + 1;
                end
            end
        end
        
        % Normalize AoA & ToF
        aoa_max = max(abs(full_measurement_matrix(:, 1)));
        tof_max = max(abs(full_measurement_matrix(:, 2)));
        full_measurement_matrix(:, 1) = full_measurement_matrix(:, 1) / aoa_max;
        full_measurement_matrix(:, 2) = full_measurement_matrix(:, 2) / tof_max;
        
        % Cluster AoA and ToF for each packet
        % Worked Pretty Well
        linkage_tree = linkage(full_measurement_matrix, 'ward');
        % cluster_indices_vector = cluster(linkage_tree, 'CutOff', 0.45, 'criterion', 'distance');
        % cluster_indices_vector = cluster(linkage_tree, 'CutOff', 0.85, 'criterion', 'distance');
        cluster_indices_vector = cluster(linkage_tree, 'CutOff', 1.0, 'criterion', 'distance');
        cluster_count_vector = zeros(0, 1);
        num_clusters = 0;
        for ii = 1:size(cluster_indices_vector, 1)
            if ~ismember(cluster_indices_vector(ii), cluster_count_vector)
                cluster_count_vector(size(cluster_count_vector, 1) + 1, 1) = cluster_indices_vector(ii);
                num_clusters = num_clusters + 1;
            end
        end
        if ~OUTPUT_FIGURES_SUPPRESSED
            % Dendrogram
            %{
            dendrogram_figure_name = sprintf('Dendrogram for file: %s', data_files{data_file_index});
            figure('Name', dendrogram_figure_name, 'NumberTitle', 'off')
            dendrogram(linkage_tree, 'ColorThreshold', 'default')
            set(gca, 'YTick', linspace(0, 10, 100));
            title(dendrogram_figure_name)
            %}
        end
        
        % Collect data and indices into cluster-specific cell arrays
        clusters = cell(num_clusters, 1);
        cluster_indices = cell(num_clusters, 1);
        for ii = 1:size(cluster_indices_vector, 1)
            % Save off the data
            tail_index = size(clusters{cluster_indices_vector(ii, 1)}, 1) + 1;
            clusters{cluster_indices_vector(ii, 1)}(tail_index, :) = full_measurement_matrix(ii, :);
            % Save off the indexes for the data
            cluster_index_tail_index = size(cluster_indices{cluster_indices_vector(ii, 1)}, 1) + 1;
            cluster_indices{cluster_indices_vector(ii, 1)}(cluster_index_tail_index, 1) = ii;
        end
        
        %%{
        % Delete outliers from each cluster
        if ~OUTPUT_SUPPRESSED
            fprintf('Deleting outliers and clusters deemed outliers....\n')
        end
        for ii = 1:size(clusters, 1)
            % Delete clusters that are < 5% of the size of the number of packets
            if size(clusters{ii}, 1) < (0.05 * num_packets)
                clusters{ii} = [];
                cluster_indices{ii} = [];
                if ~OUTPUT_SUPPRESSED
                    fprintf('Entire outlier cluster deleted: %d\n', ii)
                end
                continue;
            end
            
            if ~OUTPUT_SUPPRESSED
                fprintf('Outliers from cluster %d\n', ii)
            end
            alpha = 0.05;
            [~, outlier_indices, ~] = deleteoutliers(clusters{ii}(:, 1), alpha);
            cluster_indices{ii}(outlier_indices(:), :) = [];
            clusters{ii}(outlier_indices(:), :) = [];
            
            alpha = 0.05;
            [~, outlier_indices, ~] = deleteoutliers(clusters{ii}(:, 2), alpha);
            cluster_indices{ii}(outlier_indices(:), :) = [];
            clusters{ii}(outlier_indices(:), :) = [];
        end
        %%}
        
        cluster_plot_style = {'bo', 'go', 'ro', 'ko', ...
                        'bs', 'gs', 'rs', 'ks', ...
                        'b^', 'g^', 'r^', 'k^', ... 
                        'bp', 'gp', 'rp', 'kp', ... 
                        'b*', 'g*', 'r*', 'k*', ... 
                        'bh', 'gh', 'rh', 'kh', ... 
                        'bx', 'gx', 'rx', 'kx', ... 
                        'b<', 'g<', 'r<', 'k<', ... 
                        'b>', 'g>', 'r>', 'k>', ... 
                        'b+', 'g+', 'r+', 'k+', ... 
                        'bd', 'gd', 'rd', 'kd', ... 
                        'bv', 'gv', 'rv', 'kv', ... 
                        'b.', 'g.', 'r.', 'k.', ... 
                        %{
                        'co', 'mo', 'yo', 'wo', ...
                        'cs', 'ms', 'ys', 'ws', ...
                        'c^', 'm^', 'y^', 'w^', ... 
                        'cp', 'mp', 'yp', 'wp', ... 
                        'c*', 'm*', 'y*', 'w*', ... 
                        'ch', 'mh', 'yh', 'wh', ... 
                        'cx', 'mx', 'yx', 'wx', ... 
                        'c<', 'm<', 'y<', 'w<', ... 
                        'c>', 'm>', 'y>', 'w>', ... 
                        'c+', 'm+', 'y+', 'w+', ... 
                        'cd', 'md', 'yd', 'wd', ... 
                        'cv', 'mv', 'yv', 'wv', ... 
                        'c.', 'm.', 'y.', 'w.', ... 
                        %}
        };
        
        %% TODO: Tune parameters
        % Good base: 5, 10000, 75000, 0 (in order)
        % Likelihood parameters
        weight_num_cluster_points = 5;
        weight_aoa_variance = 50000; % prev = 10000; prev = 100000;
        weight_tof_variance = 100000;
        weight_tof_mean = 1000; % prev = 50; % prev = 10;
        constant_offset = 300;
        % Compute likelihoods
        likelihood = zeros(length(clusters), 1);
        cluster_aoa = zeros(length(clusters), 1);
        max_likelihood_index = -1;
        top_likelihood_indices = [-1; -1; -1;];% -1; -1;];
        for ii = 1:length(clusters)
            % Ignore clusters of size 1
            if size(clusters{ii}, 1) == 0
                continue
            end
            % Initialize variables
            num_cluster_points = size(clusters{ii}, 1);
            aoa_mean = 0;
            tof_mean = 0;
            aoa_variance = 0;
            tof_variance = 0;
            % Compute Means
            for jj = 1:num_cluster_points
                aoa_mean = aoa_mean + clusters{ii}(jj, 1);
                tof_mean = tof_mean + clusters{ii}(jj, 2);
            end
            aoa_mean = aoa_mean / num_cluster_points;
            tof_mean = tof_mean / num_cluster_points;
            % Compute Variances
            for jj = 1:num_cluster_points
                aoa_variance = aoa_variance + (clusters{ii}(jj, 1) - aoa_mean)^2;
                tof_variance = tof_variance + (clusters{ii}(jj, 2) - tof_mean)^2;
            end
            aoa_variance = aoa_variance / (num_cluster_points - 1);
            tof_variance = tof_variance / (num_cluster_points - 1);
            % Compute Likelihood
            exp_body = weight_num_cluster_points * num_cluster_points ...
                    - weight_aoa_variance * aoa_variance ...
                    - weight_tof_variance * tof_variance ...
                    - weight_tof_mean * tof_mean ...
                    - constant_offset;
            likelihood(ii, 1) = exp_body;%exp(exp_body);
            % Compute Cluster Average AoA
            for jj = 1:size(clusters{ii}, 1)
                cluster_aoa(ii, 1) = cluster_aoa(ii, 1) + aoa_max * clusters{ii}(jj, 1);
            end
            cluster_aoa(ii, 1) = cluster_aoa(ii, 1) / size(clusters{ii}, 1);
            if ~OUTPUT_SUPPRESSED
                % Output
                fprintf('\nCluster Properties for cluster %d\n', ii)
                fprintf('Num Cluster Points: %d, Weighted Num Cluster Points: %d\n', ...
                        num_cluster_points, (weight_num_cluster_points * num_cluster_points))
                fprintf('AoA Variance: %.9f, Weighted AoA Variance: %.9f\n', ...
                        aoa_variance, (weight_aoa_variance * aoa_variance))
                fprintf('ToF Variance: %.9f, Weighted ToF Variance: %.9f\n', ...
                        tof_variance, (weight_tof_variance * tof_variance))
                fprintf('AoA Mean %.9f\n', aoa_mean)
                fprintf('ToF Mean: %.9f, Weighted ToF Mean: %.9f\n', ...
                        tof_mean, (weight_tof_mean * tof_mean))
                fprintf('Exponential Body: %.9f\n', exp_body)
                fprintf('Cluster %d has formatting: %s, AoA: %f, and likelihood: %f\n', ...
                        ii, cluster_plot_style{ii}, cluster_aoa(ii, 1), likelihood(ii, 1))
            end
            % Check for maximum likelihood
            if max_likelihood_index == -1 ...
                    || likelihood(ii, 1) > likelihood(max_likelihood_index, 1)
                max_likelihood_index = ii;
            end
            % Record the top maximum likelihoods
            for jj = 1:size(top_likelihood_indices, 1)
                % Replace empty slot
                if top_likelihood_indices(jj, 1) == -1
                    top_likelihood_indices(jj, 1) = ii;
                    break;
                % Add somewhere in the list
                elseif likelihood(ii, 1) > likelihood(top_likelihood_indices(jj, 1), 1)
                    % Shift indices down
                    for kk = size(top_likelihood_indices, 1):-1:(jj + 1)
                        top_likelihood_indices(kk, 1) = top_likelihood_indices(kk - 1, 1);
                    end
                    top_likelihood_indices(jj, 1) = ii;
                    break;
                % Add an extra item to the list because the likelihoods are all equal...
                elseif likelihood(ii, 1) == likelihood(top_likelihood_indices(jj, 1), 1) ...
                        && jj == size(top_likelihood_indices, 1)
                    top_likelihood_indices(jj + 1, 1) = ii;
                    break;
                end
            end
        end
        if ~OUTPUT_SUPPRESSED
            fprintf('\nThe cluster with the maximum likelihood is cluster %d\n', max_likelihood_index)
            fprintf('The top clusters are: ')
            for jj = 1:size(top_likelihood_indices, 1)
                if top_likelihood_indices(jj, 1) ~= -1
                    fprintf('%d, ', top_likelihood_indices(jj, 1));
                end
            end
            fprintf('\n')
            fprintf('The clusters have AoAs: ')
            for jj = 1:size(top_likelihood_indices, 1)
                if top_likelihood_indices(jj, 1) ~= -1
                    fprintf('%g, ', cluster_aoa(top_likelihood_indices(jj, 1), 1));
                end
            end
            fprintf('\n')
            fprintf('The clusters have plot point designations: ')
            for jj = 1:size(top_likelihood_indices, 1)
                if top_likelihood_indices(jj, 1) ~= -1
                    fprintf('%s, ', ...
                            cluster_plot_style{top_likelihood_indices(jj, 1)})
                end
            end
            fprintf('\n')
            fprintf('The clusters have likelihoods: ')
            for jj = 1:size(top_likelihood_indices, 1)
                if top_likelihood_indices(jj, 1) ~= -1
                    fprintf('%g, ', ...
                            likelihood(top_likelihood_indices(jj, 1), 1))
                end
            end
            fprintf('\n')
        end
            
        % Plot AoA & ToF
        if OUTPUT_AOA_VS_TOF_PLOT && ~OUTPUT_SUPPRESSED && ~OUTPUT_FIGURES_SUPPRESSED
            figure_name_string = sprintf('%s: AoA vs ToF Plot', data_files{data_file_index});
            figure('Name', figure_name_string, 'NumberTitle', 'off')
            hold on
            % Plot the data from each cluster and draw a circle around each cluster 
            for ii = 1:size(cluster_indices, 1)
                % Some clusters may all be considered outliers...we'll see how this affects the 
                % results, but it shouldn't result in a crash!!
                if isempty(cluster_indices{ii})
                    continue
                end
                % If there's an index out of bound error, 'cluster_plot_style' is to blame
                plot(full_measurement_matrix(cluster_indices{ii, 1}, 1) * aoa_max, ...
                        full_measurement_matrix(cluster_indices{ii}, 2), ...
                        cluster_plot_style{ii}, ...
                        'MarkerSize', 8, ...
                        'LineWidth', 2.5)
                % Compute Means
                num_cluster_points = size(cluster_indices{ii}, 1);
                aoa_mean = 0;
                tof_mean = 0;
                for jj = 1:num_cluster_points
                    % Denormalize AoA for presentation
                    aoa_mean = aoa_mean + (aoa_max * clusters{ii}(jj, 1));
                    tof_mean = tof_mean + clusters{ii}(jj, 2);
                end
                aoa_mean = aoa_mean / num_cluster_points;
                tof_mean = tof_mean / num_cluster_points;
                cluster_text = sprintf('Size: %d', num_cluster_points);
                text(aoa_mean + 5, tof_mean, cluster_text)
                drawnow
            end

            [ellipse_x, ellipse_y] = compute_ellipse(...
                    clusters{max_likelihood_index}(:, 1) * aoa_max, ...
                    clusters{max_likelihood_index}(:, 2));
            plot(ellipse_x, ellipse_y, 'c-', 'LineWidth', 3)
            xlabel('Angle of Arrival (AoA)')
            ylabel('(Normalized) Time of Flight (ToF)')
            title('Angle of Arrival vs. (Normalized) Time of Flight')
            grid on
            hold off
        end
        
        % Select AoA
        max_likelihood_average_aoa = cluster_aoa(max_likelihood_index, 1);
        if ~OUTPUT_SUPPRESSED
            fprintf('The Estimated Angle of Arrival for data set %s is %f\n', ...
                    data_files{data_file_index}, max_likelihood_average_aoa)
        end
        % Profit
        output_top_aoas = cluster_aoa(top_likelihood_indices);
    end
end

%% Computes ellipse totally enclosing the points defined by x and y, includes room for markers, etc.
% x         -- the x coordinates of the points that the ellipse should enclose
% y         -- the y coordinates of the points that the ellipse should enclose
% Return:
% ellipse_x -- the x coordinates of the enclosing ellipse
% ellipse_y -- the y coordinates of the enclosing ellipse
function [ellipse_x, ellipse_y] = compute_ellipse(x, y)
    % Buffer room for each dimension
    marker_adjustment_quantity_x = 4;
    marker_adjustment_quantity_y = 0.05;
    % Find centroid
    centroid_x = sum(x) / length(x);
    centroid_y = sum(y) / length(y);
    % Find max difference between points in each dimension (diameter)
    % x
    diameter_x = 0;
    for ii = 1:length(x)
        for jj = 1:length(x)
            if abs(x(ii) - x(jj)) > diameter_x
                diameter_x = abs(x(ii) - x(jj));
            end
        end
    end
    radius_x = diameter_x / 2;
    radius_x = radius_x + marker_adjustment_quantity_x; 
    % y
    diameter_y = 0;
    for ii = 1:length(y)
        for jj = 1:length(y)
            if abs(y(ii) - y(jj)) > diameter_y
                diameter_y = abs(y(ii) - y(jj));
            end
        end
    end
    radius_y = diameter_y / 2;
    radius_y = radius_y + marker_adjustment_quantity_y;
    % Generate points of ellipse
    t = 0:0.001:(2 * pi);
    ellipse_x = radius_x * cos(t) + centroid_x;
    ellipse_y = radius_y * sin(t) + centroid_y;
end

%% Run MUSIC algorithm with SpotFi method including ToF and AoA
% x                -- the signal matrix
% antenna_distance -- the distance between the antennas in the linear array
% frequency        -- the frequency of the signal being localized
% sub_freq_delta   -- the difference between subcarrier frequencies
% data_name        -- the name of the data file being operated on, used for labeling figures
% Return:
% estimated_aoas   -- the angle of arrivals that gave peaks from running MUSIC, as a vector
% estimated_tofs   -- the time of flights that gave peaks on the estimated_aoas from running music.
%                         This is a matrix with dimensions [length(estimated_aoas, ), length(tau)].
%                         The columns are zero padded at the ends to handle different peak counts 
%                           across different AoAs.
%                         I.E. if there are three AoAs then there will be three rows in 
%                           estimated_tofs
function [estimated_aoas, estimated_tofs] = aoa_tof_music(x, ...
        antenna_distance, frequency, sub_freq_delta, data_name)
    %% DEBUG AND OUTPUT VARIABLES-----------------------------------------------------------------%%
    globals_init();
    % Debug Variables
    global DEBUG_PATHS
    global DEBUG_PATHS_LIGHT
    
    % Output Variables
    global OUTPUT_AOAS
    global OUTPUT_TOFS
    global OUTPUT_AOA_MUSIC_PEAK_GRAPH
    global OUTPUT_TOF_MUSIC_PEAK_GRAPH
    global OUTPUT_AOA_TOF_MUSIC_PEAK_GRAPH
    global OUTPUT_SELECTIVE_AOA_TOF_MUSIC_PEAK_GRAPH
    global OUTPUT_SUPPRESSED
    global OUTPUT_FIGURES_SUPPRESSED
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
    % Data covarivance matrix
    R = x * x'; 
    % Find the eigenvalues and eigenvectors of the covariance matrix
    [eigenvectors, eigenvalue_matrix] = eig(R);
    % Find max eigenvalue for normalization
    max_eigenvalue = -1111;
    for ii = 1:size(eigenvalue_matrix, 1)
        if eigenvalue_matrix(ii, ii) > max_eigenvalue
            max_eigenvalue = eigenvalue_matrix(ii, ii);
        end
    end
    
    if DEBUG_PATHS && ~OUTPUT_SUPPRESSED
        fprintf('Normalized Eigenvalues of Covariance Matrix\n')
    end
    for ii = 1:size(eigenvalue_matrix, 1)
        eigenvalue_matrix(ii, ii) = eigenvalue_matrix(ii, ii) / max_eigenvalue;
        if DEBUG_PATHS && ~OUTPUT_SUPPRESSED
            % Suppress most print statements...
            if ii > 20
                fprintf('Index: %d, eigenvalue: %f\n', ii, eigenvalue_matrix(ii, ii))
                if ii + 1 <= size(eigenvalue_matrix, 1)
                    fprintf('Decrease Factor %f:\n', ...
                            ((eigenvalue_matrix(ii + 1, ii + 1) / max_eigenvalue) ...
                                / eigenvalue_matrix(ii, ii)))
                end
            end
        end
    end
    
    % Find the largest decrease ratio that occurs between the last 10 elements (largest 10 elements)
    % and is not the first decrease (from the largest eigenvalue to the next largest)
    % Compute the decrease factors between each adjacent pair of elements, except the first decrease
    start_index = size(eigenvalue_matrix, 1) - 2;
    end_index = start_index - 10;
    decrease_ratios = zeros(start_index - end_index + 1, 1);
    k = 1;
    for ii = start_index:-1:end_index
        temp_decrease_ratio = eigenvalue_matrix(ii + 1, ii + 1) / eigenvalue_matrix(ii, ii);
        decrease_ratios(k, 1) = temp_decrease_ratio;
        k = k + 1;
    end
    if DEBUG_PATHS_LIGHT && ~OUTPUT_SUPPRESSED
        fprintf('\n')
    end
    [max_decrease_ratio, max_decrease_ratio_index] = max(decrease_ratios);
    if DEBUG_PATHS && ~OUTPUT_SUPPRESSED
        fprintf('Max Decrease Ratio: %f\n', max_decrease_ratio)
        fprintf('Max Decrease Ratio Index: %d\n', max_decrease_ratio_index)
    end

    index_in_eigenvalues = size(eigenvalue_matrix, 1) - max_decrease_ratio_index;
    num_computed_paths = size(eigenvalue_matrix, 1) - index_in_eigenvalues + 1;
    
    if (DEBUG_PATHS || DEBUG_PATHS_LIGHT) && ~OUTPUT_SUPPRESSED
        fprintf('True number of computed paths: %d\n', num_computed_paths)
        for ii = size(eigenvalue_matrix, 1):-1:end_index
            fprintf('%g, ', eigenvalue_matrix(ii, ii))
        end
        fprintf('\n')
    end
    
    % Estimate noise subspace
    column_indices = 1:(size(eigenvalue_matrix, 1) - num_computed_paths);
    eigenvectors = eigenvectors(:, column_indices); 
    % Peak search
    % Angle in degrees (converts to radians in phase calculations)
    %% TODO: Tuning theta too??
    theta = -90:1:90; 
    % time in milliseconds
    %% TODO: Tuning tau....
    %tau = 0:(1.0 * 10^-9):(50 * 10^-9);
    tau = 0:(100.0 * 10^-9):(3000 * 10^-9);
    Pmusic = zeros(length(theta), length(tau));
    % Angle of Arrival Loop (AoA)
    for ii = 1:length(theta)
        % Time of Flight Loop (ToF)
        for jj = 1:length(tau)
            steering_vector = compute_steering_vector(theta(ii), tau(jj), ...
                    frequency, sub_freq_delta, antenna_distance);
            PP = steering_vector' * (eigenvectors * eigenvectors') * steering_vector;
            Pmusic(ii, jj) = abs(1 /  PP);
        end
    end

    % Convert to decibels
    % ToF loop
    for jj = 1:size(Pmusic, 2)
        % AoA loop
        for ii = 1:size(Pmusic, 1)
            Pmusic(ii, jj) = 10 * log10(Pmusic(ii, jj));% / max(Pmusic(:, jj))); 
            Pmusic(ii, jj) = abs(Pmusic(ii, jj));
        end
    end

    if OUTPUT_AOA_TOF_MUSIC_PEAK_GRAPH && ~OUTPUT_SUPPRESSED && ~OUTPUT_FIGURES_SUPPRESSED
        % Theta (AoA) & Tau (ToF) 3D Plot
        figure('Name', 'AoA & ToF MUSIC Peaks', 'NumberTitle', 'off')
        mesh(tau, theta, Pmusic)
        xlabel('Time of Flight')
        ylabel('Angle of Arrival in degrees')
        zlabel('Spectrum Peaks')
        title('AoA and ToF Estimation from Modified MUSIC Algorithm')
        grid on
    end

    if (DEBUG_PATHS || OUTPUT_AOA_MUSIC_PEAK_GRAPH) ...
            && ~OUTPUT_SUPPRESSED && ~OUTPUT_FIGURES_SUPPRESSED
        % Theta (AoA)
        figure_name_string = sprintf('%s: Number of Paths: %d', data_name, num_computed_paths);
        figure('Name', figure_name_string, 'NumberTitle', 'off')
        plot(theta, Pmusic(:, 1), '-k')
        xlabel('Angle, \theta')
        ylabel('Spectrum function P(\theta, \tau)  / dB')
        title('AoA Estimation as a function of theta')
        grid on
    end

    % Find AoA peaks
    [~, aoa_peak_indices] = findpeaks(Pmusic(:, 1));
    estimated_aoas = theta(aoa_peak_indices);
    if OUTPUT_AOAS && ~OUTPUT_SUPPRESSED
        fprintf('Estimated AoAs\n')
        estimated_aoas
    end

    if OUTPUT_SELECTIVE_AOA_TOF_MUSIC_PEAK_GRAPH && ~OUTPUT_SUPPRESSED && ~OUTPUT_FIGURES_SUPPRESSED
        % Theta (AoA) & Tau (ToF) 3D Plot
        figure('Name', 'Selective AoA & ToF MUSIC Peaks, with only peaked AoAs', 'NumberTitle', 'off')
        mesh(tau, estimated_aoas, Pmusic(aoa_peak_indices, :))
        xlabel('Time of Flight')
        ylabel('Angle of Arrival in degrees')
        zlabel('Spectrum Peaks')
        title('AoA and ToF Estimation from Modified MUSIC Algorithm')
        grid on
    end
    
    if OUTPUT_TOF_MUSIC_PEAK_GRAPH && ~OUTPUT_SUPPRESSED && ~OUTPUT_FIGURES_SUPPRESSED
        % Tau (ToF)
        for ii = 1:1%length(estimated_aoas)
            figure_name_string = sprintf('ToF Estimation as a Function of Tau w/ AoA: %f', ...
                    estimated_aoas(ii));
            figure('Name', figure_name_string, 'NumberTitle', 'off')
            plot(tau, Pmusic(ii, :), '-k')
            xlabel('Time of Flight \tau / degree')
            ylabel('Spectrum function P(\theta, \tau)  / dB')
            title(figure_name_string)
            grid on
        end
    end
    
    % Find ToF peaks
    time_peak_indices = zeros(length(aoa_peak_indices), length(tau));
    % AoA loop (only looping over peaks in AoA found above)
    for ii = 1:length(aoa_peak_indices)
        aoa_index = aoa_peak_indices(ii);
        % For each AoA, find ToF peaks
        [peak_values, tof_peak_indices] = findpeaks(Pmusic(aoa_index, :));
        if isempty(tof_peak_indices)
            if ~OUTPUT_SUPPRESSED
                fprintf('\n\nNO PEAKS FOR TIME OF FLIGHT. SELECTING THE FIRST TOF. \n\n')
            end
            tof_peak_indices = 1;
        end
        if OUTPUT_TOFS && ~OUTPUT_SUPPRESSED
            fprintf('Time of Flight Peaks along Angle of Arrival %f\n', theta(aoa_index))
            fprintf('Found %d peaks\n', length(peak_values))
            %tau(tof_peak_indices)
        end
        % Pad result with -1 so we don't have a jagged matrix (and so we can do < 0 testing)
        negative_ones_for_padding = -1 * ones(1, length(tau) - length(tof_peak_indices));
        time_peak_indices(ii, :) = horzcat(tau(tof_peak_indices), negative_ones_for_padding);
    end

    % Set return values
    % AoA is now a column vector
    estimated_aoas = transpose(estimated_aoas);
    % ToF is now a length(estimated_aoas) x length(tau) matrix, with -1 padding for unused cells
    estimated_tofs = time_peak_indices;
end

%% Computes the steering vector for SpotFi. 
% Each steering vector covers 2 antennas on 15 subcarriers each.
% theta           -- the angle of arrival (AoA) in degrees
% tau             -- the time of flight (ToF)
% freq            -- the central frequency of the signal
% sub_freq_delta  -- the frequency difference between subcarrier
% ant_dist        -- the distance between each antenna
% Return:
% steering_vector -- the steering vector evaluated at theta and tau
%
% NOTE: All distance measurements are in meters
function steering_vector = compute_steering_vector(theta, tau, freq, sub_freq_delta, ant_dist)
    steering_vector = zeros(30, 1);
    k = 1;
    base_element = 1;
    for ii = 1:2
        for jj = 1:15
            steering_vector(k, 1) = base_element * omega_tof_phase(tau, sub_freq_delta)^(jj - 1);
            k = k + 1;
        end
        base_element = base_element * phi_aoa_phase(theta, freq, ant_dist);
    end
end

%% Compute the phase shifts across subcarriers as a function of ToF
% tau             -- the time of flight (ToF)
% frequency_delta -- the frequency difference between adjacent subcarriers
% Return:
% time_phase      -- complex exponential representing the phase shift from time of flight
function time_phase = omega_tof_phase(tau, sub_freq_delta)
    time_phase = exp(-1i * 2 * pi * sub_freq_delta * tau);
end

%% Compute the phase shifts across the antennas as a function of AoA
% theta       -- the angle of arrival (AoA) in degrees
% frequency   -- the frequency of the signal being used
% d           -- the spacing between antenna elements
% Return:
% angle_phase -- complex exponential representing the phase shift from angle of arrival
function angle_phase = phi_aoa_phase(theta, frequency, d)
    % Speed of light (in m/s)
    c = 3.0 * 10^8;
    % Convert to radians
    theta = theta / 180 * pi;
    angle_phase = exp(-1i * 2 * pi * d * sin(theta) * (frequency / c));
end

%% Creates the smoothed CSI matrix by rearranging the various csi values in the default CSI matrix.
% csi          -- the regular CSI matrix to use for creating the smoothed CSI matrix
% Return:
% smoothed_csi -- smoothed CSI matrix following the construction put forth in the SpotFi paper.
%                   Each column in the matrix includes data from 2 antennas and 15 subcarriers each.
%                   Has dimension 30x32. 
function smoothed_csi = smooth_csi(csi)
    smoothed_csi = zeros(size(csi, 2), size(csi, 2));
    % Antenna 1 (values go in the upper left quadrant)
    m = 1;
    for ii = 1:1:15
        n = 1;
        for j = ii:1:(ii + 15)
            smoothed_csi(m, n) = csi(1, j); % 1 + sqrt(-1) * j;
            n = n + 1;
        end
        m = m + 1;
    end
    
    % Antenna 2
    % Antenna 2 has its values in the top right and bottom left
    % quadrants, the first for loop handles the bottom left, the second for
    % loop handles the top right
    
    % Bottom left of smoothed csi matrix
    for ii = 1:1:15
        n = 1;
        for j = ii:1:(ii + 15)
            smoothed_csi(m, n) = csi(2, j); % 2 + sqrt(-1) * j;
            n = n + 1;
        end
        m = m + 1;
    end
    
    % Top right of smoothed csi matrix
    m = 1;
    for ii = 1:1:15
        n = 17;
        for j = ii:1:(ii + 15)
            smoothed_csi(m, n) = csi(2, j); %2 + sqrt(-1) * j;
            n = n + 1;
        end
        m = m + 1;
    end
    
    % Antenna 3 (values go in the lower right quadrant)
    for ii = 1:1:15
        n = 17;
        for j = ii:1:(ii + 15)
            smoothed_csi(m, n) = csi(3, j); %3 + sqrt(-1) * j;
            n = n + 1;
        end
        m = m + 1;
    end
end

%% Time of Flight (ToF) Sanitization Algorithm, find a linear fit for the unwrapped CSI phase
% csi_matrix -- the CSI matrix whose phase is to be adjusted
% delta_f    -- the difference in frequency between subcarriers
% Return:
% csi_matrix -- the same CSI matrix with modified phase
function [csi_matrix, phase_matrix] = spotfi_algorithm_1(csi_matrix, delta_f, packet_one_phase_matrix)
    %% Time of Flight (ToF) Sanitization Algorithm
    %  Obtain a linear fit for the phase
    %  Using the expression:
    %      argmin{\rho} \sum_{m,n = 1}^{M, N} (\phi_{i}(m, n) 
    %          + 2 *\pi * f_{\delta} * (n - 1) * \rho + \beta)^2
    %
    %  Arguments:
    %  M is the number of antennas
    %  N is the number of subcarriers
    %  \phi_{i}(m, n) is the phase for the nth subcarrier, 
    %      on the mth antenna, for the ith packet
    %  f_{\delta} is the frequency difference between the adjacent
    %      subcarriers
    %  \rho and \beta are the linear fit variables
    %
    % Unwrap phase from CSI matrix
    R = abs(csi_matrix);
    phase_matrix = unwrap(angle(csi_matrix), pi, 2);
    
    % Parse input args
    if nargin < 3
        packet_one_phase_matrix = phase_matrix;
    end

    % STO is the same across subcarriers....
    % Data points are:
    % subcarrier_index -> unwrapped phase on antenna_1
    % subcarrier_index -> unwrapped phase on antenna_2
    % subcarrier_index -> unwrapped phase on antenna_3
    fit_X(1:30, 1) = 1:1:30;
    fit_X(31:60, 1) = 1:1:30;
    fit_X(61:90, 1) = 1:1:30;
    fit_Y = zeros(90, 1);
    for i = 1:size(phase_matrix, 1)
        for j = 1:size(phase_matrix, 2)
            fit_Y((i - 1) * 30 + j) = packet_one_phase_matrix(i, j);
        end
    end

    % Linear fit is common across all antennas
    result = polyfit(fit_X, fit_Y, 1);
    tau = result(1);
        
    for m = 1:size(phase_matrix, 1)
        for n = 1:size(phase_matrix, 2)
            % Subtract the phase added from sampling time offset (STO)
            phase_matrix(m, n) = packet_one_phase_matrix(m, n) + (2 * pi * delta_f * (n - 1) * tau);
        end
    end
    
    % Reconstruct the CSI matrix with the adjusted phase
    csi_matrix = R .* exp(1i * phase_matrix);
end