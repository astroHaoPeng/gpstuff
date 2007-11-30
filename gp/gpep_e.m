function [e, edata, eprior, site_tau, site_nu, L, La2, b] = gpep_e(w, gp, x, y, param, varargin)
%GP2_E	Evaluate error function for Gaussian Process.
%
%	Description
%	E = GPEP_E(W, GP, P, T, PARAM) takes a gp data structure GP together
%	with a matrix P of input vectors and a matrix T of target vectors,
%	and evaluates the error function E.  Each row of P
%	corresponds to one input vector and each row of T corresponds to one
%	target vector.
%
%	[E, EDATA, EPRIOR] = GPEP_E(W, GP, P, T, PARAM) also returns the data and
%	prior components of the total error.
%
%	See also
%	
%

% Copyright (c) 2007      Jarno Vanhatalo, Jaakko Riihim�ki

% This software is distributed under the GNU General Public 
% License (version 2 or later); please refer to the file 
% License.txt, included with the software, for details.
    
    if strcmp(w, 'init')
        w0 = rand(size(gp_pak(gp, param)));
        e0=[]; 
        edata0= inf; 
        eprior0=[];
        nutilde0 = zeros(size(y));
        tautilde0 = zeros(size(y));
        myy0 = zeros(size(y));
        L0 = [];
        myy=zeros(size(y));
        n0 = size(x,1);
        La20 = [];
        b0 = 0;
    
        ep_algorithm(gp_pak(gp,param), gp, x, y, param, varargin);
        
        gp.fh_e = @ep_algorithm;
        e = gp;
    else
        [e, edata, eprior, site_tau, site_nu, L, La2, b] = feval(gp.fh_e, w, gp, x, y, param, varargin);
        
    end
    
    function [e, edata, eprior, tautilde, nutilde, L, La2, b] = ep_algorithm(w, gp, x, y, param, varargin)

        if abs(w-w0) < 1e-8
            % The covariance function parameters haven't changed so just 
            % return the Energy and the site parameters that are saved
            e = e0;
            edata = edata0;
            eprior = eprior0;
            nutilde = nutilde0;
            myy = myy0;
            tautilde = tautilde0;
            L = L0;
            La2 = La20;
            b = b0;
        else
            % Conduct evaluation for the energy and the site parameters
            gp=gp_unpak(gp, w, param);
            ncf = length(gp.cf);
            n = length(x);

            % ep iteration parameters
            iter=1;
            maxiter = gp.ep_opt.maxiter;
            tol = gp.ep_opt.tol;
            nutilde = zeros(size(y));
            tautilde = zeros(size(y));
            myy = zeros(size(y));
            logZep_tmp=0; logZep=Inf;
            
            switch gp.likelih
              case 'poisson'
                M_0=[];
            end
            
            % =================================================
            % First Evaluate the data contribution to the error    
            switch gp.type
                % ============================================================
                % FULL
                % ============================================================
              case 'FULL'   % A full GP
                [K,C] = gp_trcov(gp, x);
                Sigm = C;
                Stildesqroot=zeros(n);
                
                % The EP -algorithm
                while iter<=maxiter & abs(logZep_tmp-logZep)>tol
                    
                    logZep_tmp=logZep;
                    muvec_i = zeros(n,1); sigm2vec_i = zeros(n,1);
                    for i1=1:n
                        % approximate cavity parameters
                        tau_i=Sigm(i1,i1)^-1-tautilde(i1);
                        vee_i=Sigm(i1,i1)^-1*myy(i1)-nutilde(i1);

                        myy_i=vee_i/tau_i;
                        sigm2_i=tau_i^-1;

                        % marginal moments
                        [muhati, sigm2hati] = marginalMoments12(gp.likelih);
                
                        % update site parameters
                        deltatautilde=sigm2hati^-1-tau_i-tautilde(i1);
                        tautilde(i1)=tautilde(i1)+deltatautilde;
                        nutilde(i1)=sigm2hati^-1*muhati-vee_i;

                        apu = deltatautilde^-1+Sigm(i1,i1);
                        apu = (Sigm(:,i1)/apu)*Sigm(:,i1)';
                        Sigm = Sigm - apu;
                        %Sigm=Sigm-(deltatautilde^-1+Sigm(i1,i1))^-1*(Sigm(:,i1)*Sigm(:,i1)');
                        myy=Sigm*nutilde;
                        
                        muvec_i(i1,1)=myy_i;
                        sigm2vec_i(i1,1)=sigm2_i;
                    end
                    
                    % Recompute the approximate posterior parameters
                    Stilde=tautilde;
                    Stildesqroot=diag(sqrt(tautilde));

                    % NOTICE! upper triangle matrix! cf. to
                    % line 13 in the algorithm 3.5, p. 58.
                    B=eye(n)+Stildesqroot*C*Stildesqroot;
                    L=chol(B,'lower');

                    V=(L\Stildesqroot)*C;
                    Sigm=C-V'*V; myy=Sigm*nutilde;

                    % Compute the marginal likelihood
                    % Direct formula (3.65):
                    % Sigmtilde=diag(1./tautilde);
                    % mutilde=inv(Stilde)*nutilde;
                    %
                    % logZep=-0.5*log(det(Sigmtilde+K))-0.5*mutilde'*inv(K+Sigmtilde)*mutilde+
                    %         sum(log(normcdf(y.*muvec_i./sqrt(1+sigm2vec_i))))+
                    %         0.5*sum(log(sigm2vec_i+1./tautilde))+
                    %         sum((muvec_i-mutilde).^2./(2*(sigm2vec_i+1./tautilde)))
                    
                    % 4. term & 1. term
                    term41=0.5*sum(log(1+tautilde.*sigm2vec_i))-sum(log(diag(L)));
                    
                    % 5. term (1/2 element) & 2. term
                    T=1./sigm2vec_i;
                    Cnutilde = C*nutilde;
                    L2 = V*nutilde;
                    term52 = nutilde'*Cnutilde - L2'*L2 - (nutilde'./(T+Stilde)')*nutilde;
                    term52 = term52.*0.5;
                    
                    % 5. term (2/2 element)
                    term5=0.5*muvec_i'.*(T./(Stilde+T))'*(Stilde.*muvec_i-2*nutilde);
                    
                    % 3. term
                    term3 = marginalMoment0(gp.likelih);
                    
                    logZep = -(term41+term52+term5+term3);
                    
% $$$                     if isfield(gp.ep_opt, 'display') && gp.ep_opt.display == 1
% $$$                         fprintf('The log marginal likelihood at iteration %d: %.3f \n', iter, logZep)
% $$$                     end

                    iter=iter+1;
                end
                edata = logZep;
                % Set something into La2
                La2 = B; 
                b = 0;
                % ============================================================
                % FIC
                % ============================================================                                
              case 'FIC'
                u = gp.X_u;
                m = length(u);
                
                % First evaluate needed covariance matrices
                % v defines that parameter is a vector
                [Kv_ff, Cv_ff] = gp_trvar(gp, x);  % f x 1  vector
                K_fu = gp_cov(gp, x, u);         % f x u
                K_uu = gp_trcov(gp, u);    % u x u, noiseles covariance K_uu
                K_uu = (K_uu+K_uu')./2;     % ensure the symmetry of K_uu
                Luu = chol(K_uu)';
                % Evaluate the Lambda (La) 
                % Q_ff = K_fu*inv(K_uu)*K_fu'
                % Here we need only the diag(Q_ff), which is evaluated below
                B=Luu\(K_fu');       % u x f
                Qv_ff=sum(B.^2)';
                Lav = Cv_ff-Qv_ff;   % f x 1, Vector of diagonal elements
                                     % iLaKfu = diag(iLav)*K_fu = inv(La)*K_fu

                R0 = chol(inv(K_uu));
                R = R0;
                P = K_fu;
                myy = zeros(size(y));
                eta = zeros(size(y));
                gamma = zeros(size(K_uu,1),1);
                D_vec = Lav;
                Ann=0;
                
                while iter<=maxiter & abs(logZep_tmp-logZep)>tol
                    
                    logZep_tmp=logZep;
                    muvec_i = zeros(n,1); sigm2vec_i = zeros(n,1);
                    for i1=1:n
                        % approximate cavity parameters
                        Ann = D_vec(i1) + sum((R*P(i1,:)').^2);
                        tau_i = Ann^-1-tautilde(i1);
                        vee_i = Ann^-1*myy(i1)-nutilde(i1);
                        
                        myy_i=vee_i/tau_i;
                        sigm2_i=tau_i^-1;
                        
                        % marginal moments
                        [muhati, sigm2hati] = marginalMoments12(gp.likelih);
                        
                        % update site parameters
                        deltatautilde = sigm2hati^-1-tau_i-tautilde(i1);
                        tautilde(i1) = tautilde(i1)+deltatautilde;
                        deltanutilde = sigm2hati^-1*muhati-vee_i - nutilde(i1);
                        nutilde(i1) = sigm2hati^-1*muhati-vee_i;

                        % Update the parameters
                        D_vec(i1) = D_vec(i1) - deltatautilde.*D_vec(i1).^2 ./ (1+deltatautilde.*D_vec(i1));
                        pn = P(i1,:)';
                        P(i1,:) = pn' - (deltatautilde.*D_vec(i1) ./ (1+deltatautilde.*D_vec(i1))).*pn';
                        updfact = deltatautilde./(1 + deltatautilde.*Ann);
                        if updfact > 0
                            RtRpnU = R'*(R*pn).*sqrt(updfact);
                            R = cholupdate(R, RtRpnU, '-');
                        elseif updfact < 0
                            RtRpnU = R'*(R*pn).*sqrt(abs(updfact));
                            R = cholupdate(R, RtRpnU, '+');
                        end
                        eta(i1) = eta(i1) + (deltanutilde + deltatautilde.*eta(i1)).*D_vec(i1)./(1+deltatautilde.*D_vec(i1));
                        gamma = gamma + (deltanutilde - deltatautilde.*myy(i1))./(1+deltatautilde.*D_vec(i1)) * R'*(R*pn);
                        myy = eta + P*gamma;     
                        
                        % Store cavity parameters
                        muvec_i(i1,1)=myy_i;
                        sigm2vec_i(i1,1)=sigm2_i;
                    end
                    
                    % Re-evaluate the parameters
                    temp1 = (1+Lav.*tautilde).^(-1);
                    D_vec = temp1.*Lav;
                    R0P0t = R0*K_fu';
                    temp2 = zeros(size(R0P0t));
                    for i2 = 1:length(temp1)
                        P(i2,:) = temp1(i2).*K_fu(i2,:);
                        temp2(:,i2) = R0P0t(:,i2).*tautilde(i2).*temp1(i2);
                    end
                    R = chol(inv(eye(size(R0)) + temp2*R0P0t')) * R0;
                    eta = D_vec.*nutilde;
                    gamma = R'*(R*(P'*nutilde));
                    myy = eta + P*gamma;
                    
                    
                    % Compute the marginal likelihood, see FULL model for 
                    % details about equations
                    % 
                    % First some helper parameters
                    iLaKfu = zeros(size(K_fu));  % f x u, 
                    for i=1:n
                        iLaKfu(i,:) = K_fu(i,:)./Lav(i);  % f x u 
                    end
                    A = K_uu+K_fu'*iLaKfu;  A = (A+A')./2;     % Ensure symmetry
                    A = chol(A);
                    L = iLaKfu/A;
                    Lahat = 1./Lav;
                    I = eye(size(K_uu));                    
                    Lahat = 1./Lav + tautilde;
                    for i = 1:n
                        Lhat(i,:) = L(i,:)./Lahat(i);
                    end
                    H = I-L'*Lhat;
                    B = H\L';
                    Bhat = B./repmat(Lahat',m,1);
                    
                    % 4. term & 1. term
                    Stildesqroot=sqrt(tautilde);
                    D = Stildesqroot.*Lav.*Stildesqroot + 1;
                    SsqrtKfu = K_fu.*repmat(Stildesqroot,1,m);
                    AA = K_uu + (SsqrtKfu'./repmat(D',m,1))*SsqrtKfu; AA = (AA+AA')/2;
                    AA = chol(AA,'lower');
                    term41 = - 0.5*sum(log(1+tautilde.*sigm2vec_i)) - sum(log(diag(Luu))) + sum(log(diag(AA))) + 0.5.*sum(log(D));
                    
                    % 5. term (1/2 element) & 2. term
                    T=1./sigm2vec_i;
                    term52 = -0.5*( (nutilde./Lahat)'*nutilde + (nutilde'*Lhat)*(Bhat*nutilde) - (nutilde./(T+tautilde))'*nutilde);

                    % 5. term (2/2 element)
                    term5 = - 0.5*muvec_i'.*(T./(tautilde+T))'*(tautilde.*muvec_i-2*nutilde);
                    
                    % 3. term
                    term3 = -marginalMoment0(gp.likelih);
                                                          
                    logZep = term41+term52+term5+term3;
                                                            
                    iter=iter+1;
                end
                edata = logZep;
                %L = iLaKfu;
                
                b = nutilde'.*(1 - Stildesqroot./Lahat.*Stildesqroot)' - (nutilde'*Lhat)*Bhat.*tautilde';
                L = ((repmat(Stildesqroot,1,m).*SsqrtKfu)./repmat(D',m,1)')/AA';
                La2 = 1./(Stildesqroot./D.*Stildesqroot);
                
                % ============================================================
                % FIC
                % ============================================================
              case 'PIC_BLOCK'
                u = gp.X_u;
                ind = gp.tr_index;
                m = length(u);
                
                % First evaluate needed covariance matrices
                % v defines that parameter is a vector
                K_fu = gp_cov(gp, x, u);         % f x u
                K_uu = gp_trcov(gp, u);    % u x u, noiseles covariance K_uu
                K_uu = (K_uu+K_uu')./2;     % ensure the symmetry of K_uu
                Luu = chol(K_uu)';
                % Evaluate the Lambda (La) 
                % Q_ff = K_fu*inv(K_uu)*K_fu'
                % Here we need only the blockdiag(Q_ff), which is evaluated below
                B=Luu\(K_fu');       % u x f  and B'*B = K_fu*K_uu*K_uf
                iLaKfu = zeros(size(K_fu));  % f x u
                for i=1:length(ind)
                    Qbl_ff = B(:,ind{i})'*B(:,ind{i});
                    [Kbl_ff, Cbl_ff] = gp_trcov(gp, x(ind{i},:));
                    Labl{i} = Cbl_ff - Qbl_ff;
                    Lahat{i} = inv(Labl{i});
                    iLaKfu(ind{i},:) = Lahat{i}*K_fu(ind{i},:);
                end
                A = K_uu+K_fu'*iLaKfu;
                A = (A+A')./2;     % Ensure symmetry
                A = chol(A);
                L = iLaKfu/A;
                
                for i = 1:length(ind)
                    Lhat(ind{i},:) = Lahat{i}\L(ind{i},:);
                end
                LtLhat = L'*Lhat;              
                I = eye(size(K_uu));

                iLahatnutilde = zeros(n,1);
                diag_iLahat = zeros(n,1);
                for jj=1:length(ind)
                    iLahatnutilde(ind{jj}) = Lahat{jj}\nutilde(ind{jj});
                    diag_iLahat(ind{jj}) = diag(inv(Lahat{jj}));
                end
                            
                
                % Note here Sigm is a diagonal vector, which contains the 
                % diagonal elements of the covariance matrix of the approximate posterior
                [Kv_ff, Sigm_v] = gp_trvar(gp, x);  % f x 1  vector
                H = I-L'*Lhat;
                B = H\L';
                
                % Begin the EP -algorithm
                %-----------------------------------------------
                while iter<=maxiter & abs(logZep_tmp-logZep)>tol
                
                    logZep_tmp=logZep;
                    muvec_i = zeros(n,1); sigm2vec_i = zeros(n,1);
                    for bl=1:length(ind)
                        bl_ind = ind{bl};
                        for in=1:length(bl_ind)
                            i1 = bl_ind(in);
                            % approximate cavity parameters
                            tau_i=Sigm_v(i1)^-1-tautilde(i1);
                            vee_i=Sigm_v(i1)^-1*myy(i1)-nutilde(i1);

                            myy_i=vee_i/tau_i;
                            sigm2_i=tau_i^-1;
                            
                            % marginal moments
                            [muhati, sigm2hati] = marginalMoments12(gp.likelih);
                            
                            % update site parameters
                            deltatautilde=sigm2hati^-1-tau_i-tautilde(i1);
                            tautilde(i1)=tautilde(i1)+deltatautilde;
                            nutilde(i1)=sigm2hati^-1*muhati-vee_i;

                            % Evaluate the hat parameters for approximate posterior
                            Lahat{bl}(in,in) = Lahat{bl}(in,in) + deltatautilde;
                            Lhat_old = Lhat(bl_ind,:);
                            Lhat(bl_ind,:) = Lahat{bl}\L(bl_ind,:);  % f x u
                            deltaLhat_i = Lhat_old - Lhat(bl_ind,:);
                            LtLhat = LtLhat - L(bl_ind,:)'*deltaLhat_i;

                            b = H\L(bl_ind,:)';
                            bhat = deltaLhat_i*B;
                            h = deltaLhat_i*b;
                            B = B - b*((eye(size(h))+h)\bhat);
                            for ii=1:length(ind)
                                Bhat(:,ind{ii}) = B(:,ind{ii})/Lahat{ii};
                            end
                            
                            % Update the parameters of the approximate posterior (myy and Sigm_v)
                            iLahat = inv(Lahat{bl});
                            iLahatnutilde(bl_ind) = iLahat*nutilde(bl_ind);
                            diag_iLahat(bl_ind) = diag(iLahat);
                            
                            myy = iLahatnutilde  + Lhat*(Bhat*nutilde);
                            Sigm_v = diag_iLahat + sum(Lhat.*Bhat',2);
                            H = (I-LtLhat);
                                                       
                            % Compute the diagonal of the covariance of the approximate posterior                    
                            muvec_i(i1,1)=myy_i;
                            sigm2vec_i(i1,1)=sigm2_i;
                        end
                    end
                    % Re-evaluate the H and B parameters
                    for i = 1:length(ind)
                        Lahat{i} = inv(Labl{i}) + diag(tautilde(ind{i}));
                        Lhat(ind{i},:) = Lahat{i}\L(ind{i},:);
                    end
                    H = I-L'*Lhat;
                    B = H\L';
                    
                    % Compute the marginal likelihood, see FULL model for 
                    % details about equations
                    Stildesqroot=sqrt(tautilde);
                    term41 = 0; term52 = 0;
                    for i=1:length(ind)
                        Bhat(:,ind{i}) = B(:,ind{i})/Lahat{i};                                        
                        D{i} = diag(Stildesqroot(ind{i}))*Labl{i}*diag(Stildesqroot(ind{i})) + eye(size(Labl{i}));
                        SsqrtKfu(ind{i},:) = K_fu(ind{i},:).*repmat(Stildesqroot(ind{i}),1,m);
                        iDSsqrtKfu(ind{i},:) = D{i}\SsqrtKfu(ind{i},:);
                        term41 = term41 + sum(log(diag(chol(D{i},'lower'))));
                        term52 = term52 + nutilde(ind{i})'*(Lahat{i}\nutilde(ind{i}));
                    end
                    AA = K_uu + SsqrtKfu'*iDSsqrtKfu; AA = (AA+AA')/2;
                    AA = chol(AA,'lower');
                    term41 = term41 - 0.5*sum(log(1+tautilde.*sigm2vec_i)) - sum(log(diag(Luu))) + sum(log(diag(AA)));
                    
                    % 5. term (1/2 element) & 2. term
                    T=1./sigm2vec_i;
                    term52 = -0.5*( term52 + (nutilde'*Lhat)*(Bhat*nutilde) - (nutilde./(T+tautilde))'*nutilde);

                    % 5. term (2/2 element)
                    term5 = - 0.5*muvec_i'.*(T./(tautilde+T))'*(tautilde.*muvec_i-2*nutilde);
                    
                    % 3. term
                    term3 = -marginalMoment0(gp.likelih);
                    
                    logZep = term41+term52+term5+term3;                    
                    iter=iter+1;
                end
                edata = logZep;
                %L = L2;
                
                b = zeros(1,n);
                for i=1:length(ind)
                    b(ind{i}) = nutilde(ind{i})'/Lahat{i};
                    La2{i} = inv(diag(Stildesqroot(ind{i}))*(D{i}\diag(Stildesqroot(ind{i}))));
                end
                b = nutilde' - ((b + (nutilde'*Lhat)*Bhat).*tautilde');
                
                L = (repmat(Stildesqroot,1,m).*iDSsqrtKfu)/AA';
                
              otherwise
                error('Unknown type of Gaussian process!')
            end
            
            % ======================================================================
            % Evaluate the prior contribution to the error from covariance functions
            % ======================================================================
            eprior = 0;
            for i=1:ncf
                gpcf = gp.cf{i};
                eprior = eprior + feval(gpcf.fh_e, gpcf, x, y);
            end
            
            % Evaluate the prior contribution to the error from noise functions
            if isfield(gp, 'noise')
                nn = length(gp.noise);
                for i=1:nn
                    noise = gp.noise{i};
                    eprior = eprior + feval(noise.fh_e, noise, x, y);
                end
            end
            
            % The last things to do
            if isfield(gp.ep_opt, 'display') && gp.ep_opt.display == 1
                fprintf('   Number of iterations in EP: %d \n', iter-1)
            end

            e = edata + eprior;
            
            w0 = w;
            e0 = e;
            edata0 = edata;
            eprior0 = eprior;
            nutilde0 = nutilde;
            tautilde0 = tautilde;
            myy0 = myy;
            L0 = L;
            n0 = size(x,1);
            La20 = La2;
            b0 = b;
        end
%
% ==============================================================
% Begin of the nested functions
% ==============================================================
%

% Evaluate the marginal moments

        function [muhati1, sigm2hati1] = marginalMoments12(likelihood)
            switch likelihood
                % ============================================================
                % PROBIT
                % ============================================================
              case 'probit'
                zi=y(i1)*myy_i/sqrt(1+sigm2_i);
                normp_zi = normpdf(zi);
                normc_zi = normcdf(zi);
                muhati1=myy_i+(y(i1)*sigm2_i*normp_zi)/(normc_zi*sqrt(1+sigm2_i));
                sigm2hati1=sigm2_i-(sigm2_i^2*normp_zi)/((1+sigm2_i)*normc_zi)*(zi+normp_zi/normc_zi);
                % ============================================================
                % POISSON
                % ============================================================
              case 'poisson'
                zm = @zeroth_moment;
                fm = @first_moment;
                sm = @second_moment;
                
                tol = 1e-8;
                yy = y(i1);
                avgE = gp.avgE(i1);
                % Set the limits for integration and integrate with quad
                if yy > 0
                    mean_app = log(yy./avgE);                    
                    mean_app = (myy_i/sigm2_i + mean_app.*yy)/(1/sigm2_i + yy);
                    sigm_app = sqrt((1/sigm2_i + yy)^-1);
                    %lambdaconf_fix(1) = mean_app - 6*sigm_app; lambdaconf_fix(2) = mean_app + 6*sigm_app;
                else
                    mean_app = myy_i;
                    sigm_app = sqrt(sigm2_i);
                    %lambdaconf_fix(1) = myy_i - 4*sqrt(sigm2_i); lambdaconf_fix(2) = myy_i + 4*sqrt(sigm2_i);
                end
                
                lambdaconf(1) = mean_app - 8.*sigm_app; lambdaconf(2) = mean_app + 8.*sigm_app;
                cont1 = true; cont2 = true;
                old1 = 0; old2 = 0;
                while cont1 || cont2
                    new = feval(zm, lambdaconf(1));
                    if  abs(new - old1) < tol
                        cont1 = false;
                    else
                        lambdaconf(1) = lambdaconf(1) - 2.*sigm_app;
                        old1 = new;
                    end
                    new = feval(zm, lambdaconf(2));
                    if  abs(new - old2) < tol
                        cont2 = false;
                    else
                        lambdaconf(2) = lambdaconf(2) + 2.*sigm_app;
                        old2 = new;
                    end                                        
                end
                
                % Evaluate the moments                
                [m_0, fhncnt] = quad(zm, lambdaconf(1), lambdaconf(2), tol, false);
                [m_1, fhncnt] = quad(fm, lambdaconf(1), lambdaconf(2), tol, false);
                [sigm2hati1, fhncnt] = quad(sm, lambdaconf(1), lambdaconf(2), tol, false);
                               
                % If the second central moment is less than cavity variance integrate more
                % precisely. Theoretically should be sigm2hati1 < sigm2_i
                if sigm2hati1 >= sigm2_i
                    tol = tol.^2;
                    [m_0, fhncnt] = quad(zm, lambdaconf(1), lambdaconf(2), tol, false);
                    [m_1, fhncnt] = quad(fm, lambdaconf(1), lambdaconf(2), tol, false);
                    [sigm2hati1, fhncnt] = quad(sm, lambdaconf(1), lambdaconf(2), tol, false);
                end
                % Set the mean
                muhati1 = m_1;
                M_0(i1) = m_0;
            end
            function integrand = zeroth_moment(f)
                lambda = avgE.*exp(f);
                integrand = exp(-lambda + yy.*log(lambda) - gammaln(yy+1)); % 
                integrand = integrand.*exp(-0.5 * (f-myy_i).^2./sigm2_i - log(sigm2_i)/2 - log(2*pi)/2); % 
            end
            
            function integrand = first_moment(f)
                lambda = avgE.*exp(f);
                integrand = exp(-lambda + yy.*log(lambda) - gammaln(yy+1)); % 
                integrand = f.*integrand.*exp(-0.5 * (f-myy_i).^2./sigm2_i - log(sigm2_i)/2 - log(2*pi)/2); % 
                integrand = integrand./m_0;
            end
            function integrand = second_moment(f)
                lambda = avgE.*exp(f);
                integrand = exp(-lambda + yy.*log(lambda) - gammaln(yy+1)); %  
                integrand = (f-m_1).^2.*integrand.*exp(-0.5 * (f-myy_i).^2./sigm2_i - log(sigm2_i)/2 - log(2*pi)/2); %
                integrand = integrand./m_0;
            end
        end
        
        function m_0 = marginalMoment0(likelihood)
            switch likelihood
              case 'probit'
                m_0 = sum(log(normcdf(y.*muvec_i./sqrt(1+sigm2vec_i))));
                 case 'poisson'
                   m_0 = sum(log(M_0));
            end
        end
    end
end
