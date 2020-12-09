function [f, err] = getFreq(Y)
    cross_idxs = find((Y .* circshift(Y,1)) < 0);
    if (length(cross_idxs) < 2)
        f = 0;
        err = 100;
        return;
    end
    mean_diff = mean(diff(cross_idxs));
    target = cross_idxs(1):mean_diff:length(Y);
    if length(cross_idxs) < length(target)
        err = (mean_diff/2)*(length(target) - length(cross_idxs));
    else
        err = 0;
    end
    for i = cross_idxs
        err = err + min(abs(target - i));
    end
    err = err / length(target);
    f = 1/(2*mean_diff);
return