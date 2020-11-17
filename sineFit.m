function [c,g]=sineFit(X,Y)
    s = fitoptions('Method','NonlinearLeastSquares',...
                   'Lower',[-10, 0, 0, 0],...
                   'Upper',[10, 20, 2*pi, 20],...
                   'Startpoint',[0, 0.2, 0, 1]);
    ft = fittype('offs + sin(6.283*f*x + phi)*A','coefficients',{'offs', 'f','phi','A'}, 'options', s);
    [c,g] = fit(X',double(Y'),ft);
return