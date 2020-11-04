function [newPoints] = filterStaticPoints(history, current)
    DIST_THRESHOLD = 1e-4;
    PROP_THRESHOLD = 0.8;
    curr_sz = size(current);
    h_sz = size(history);
    static_idx_list = [];
    
    for c_idx = 1:(curr_sz(1))
       curr_point = current(c_idx,:);
       n_in_hist = 0;
       for h_idx = 1:(h_sz(1))
           curr_frame = history{h_idx};
           curr_frame = curr_frame - curr_point;
           norms = vecnorm(curr_frame,2,2);
           if any(norms < DIST_THRESHOLD)
               n_in_hist = n_in_hist + 1;
           end
       end
       if (n_in_hist/(h_sz(1)) > PROP_THRESHOLD)
           static_idx_list = [static_idx_list c_idx];
       end
       disp(curr_point); 
    end
    
    out_idx = setdiff(1:curr_sz(1), static_idx_list);
    newPoints = current(out_idx,:);
return