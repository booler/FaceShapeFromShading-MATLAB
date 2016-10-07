function [normal_map] = SFS(input_file, albedo_file, normal_file, depth_file, ...
                            LoG, mat_LoG, ...
                            downsample_factor, normal_map)

I_input = im2double(imread(input_file));

I_albedo = im2double(imread(albedo_file));
I_normal = im2double(imread(normal_file));
I_normal_raw = imread(normal_file);

I_depth = load_depth_map(depth_file);

plot_depth(I_depth);
pause

if nargin > 6
    I_input = imresize(I_input, downsample_factor);
    I_albedo = imresize(I_albedo, downsample_factor);
    I_normal = imresize(I_normal, downsample_factor);
    I_normal_raw = imresize(I_normal_raw, downsample_factor);
end

if 1
    [h, w, ~] = size(I_input);
    I_albedo = imresize(I_albedo, [h, w]);
    I_normal = imresize(I_normal, [h, w]);
    I_normal_raw = imresize(I_normal_raw, [h, w]);
end

% figure;imshow(I_input);title('input');
% figure;imshow(I_albedo);title('albedo');
% figure;imshow(I_normal);title('normal');

% get the valid pixels
Inx = I_normal_raw(:,:,1); Iny = I_normal_raw(:,:,2); Inz = I_normal_raw(:,:,3);
valid_pixel_indices = intersect(intersect(find(Inx~=0), find(Iny~=0)), find(Inz~=0));
edge_pixel_indices = find_edge(I_normal_raw);
hair_pixel_indices = find_hair_pixels(I_input, valid_pixel_indices);
valid_pixel_indices = setdiff(valid_pixel_indices, edge_pixel_indices);
lighting_pixel_indices = setdiff(valid_pixel_indices, hair_pixel_indices);
size(valid_pixel_indices)
num_pixels = length(valid_pixel_indices);

% valid_pixel_mask = zeros(h, w);
% valid_pixel_mask(valid_pixel_indices) = 1;
% figure;imshow(valid_pixel_mask);

lighting_pixels_mask = zeros(h, w);
lighting_pixels_mask(lighting_pixel_indices) = 1;
figure;imshow(lighting_pixels_mask);

% initialize normal
if nargin < 8
    init_normal_map = (I_normal - 0.5) * 2.0;
    normal_map = init_normal_map;
else
    normal_map = (normal_map - 0.5) * 2.0;
    init_normal_map = imresize(normal_map, [h, w]);
end

nx0 = init_normal_map(:, :, 1);
ny0 = init_normal_map(:, :, 2);
nz0 = init_normal_map(:, :, 3);

% normals
nx = nx0(:); nx = max(-1.0, min(1.0, nx));
ny = ny0(:); ny = max(-1.0, min(1.0, ny));
nz = nz0(:); nz = max(-1.0, min(1.0, nz));

% albedo and input pixels
ar = I_albedo(:,:,1); Ir = I_input(:,:,1);
ag = I_albedo(:,:,2); Ig = I_input(:,:,2);
ab = I_albedo(:,:,3); Ib = I_input(:,:,3);

albedo_map_LoG = imfilter(I_albedo, LoG, 'replicate');
% figure;imshow(albedo_map_LoG); title('albedo LoG');

LoG_ar = albedo_map_LoG(:,:,1);
LoG_ag = albedo_map_LoG(:,:,2);
LoG_ab = albedo_map_LoG(:,:,3);

normal_map_LoG = imfilter(init_normal_map, LoG, 'replicate');
% figure;imshow(normal_map_LoG); title('normal LoG');

LoG_nx_ref = normal_map_LoG(:,:,1);
LoG_ny_ref = normal_map_LoG(:,:,2);
LoG_nz_ref = normal_map_LoG(:,:,3);

%% some preparation
good_indices = zeros(h*w*3, 1);
good_indices(valid_pixel_indices) = 1; 
good_indices(valid_pixel_indices+h*w) = 1; 
good_indices(valid_pixel_indices+h*w*2) = 1;
bad_indices = 1 - good_indices;
good_indices = logical(good_indices);
bad_indices = logical(bad_indices);

good_indices_1 = zeros(h*w,1);
good_indices_1(valid_pixel_indices) = 1;
bad_indices_1 = 1 - good_indices_1;
good_indices_1 = logical(good_indices_1);
bad_indices_1 = logical(bad_indices_1);
size(valid_pixel_indices)
good_indices_2 = zeros(h*w*2,1);
good_indices_2(valid_pixel_indices) = 1;
good_indices_2(valid_pixel_indices+h*w) = 1;
good_indices_2 = logical(good_indices_2);

for iter=1:3
    %% estimate lighting coefficients
    t_light=tic;
    Y = makeY(nx, ny, nz);
    
    A_pixels = [ar(:); ag(:); ab(:)];
    I_pixels = [Ir(:); Ig(:); Ib(:)];
    
    if iter == 1
        second_order_weight = 1;
    else
        second_order_weight = 1;
    end
    s_weights = [ones(1, 4), ones(1, 5)*second_order_weight];
    lhs = repmat(A_pixels, 1, 9) .* [Y;Y;Y] .* repmat(s_weights, size(A_pixels,1), 1);
    rhs = I_pixels;    
    
    % remove hair pixels
    lhs(hair_pixel_indices, :) = 0;
    rhs(hair_pixel_indices, :) = 0;
    
    lhs(bad_indices, :) = [];
    rhs(bad_indices, :) = [];
    
    l_lambda = 1e-16;
    l = (lhs' * lhs + l_lambda*eye(9)) \ (lhs' * rhs);
    
    Yl = Y * l;    
    
%     lighting_mask = reshape(Yl, h, w);
%     figure;imagesc(lighting_mask); title('lighting'); axis equal; colorbar; colormap gray;

%     figure; 
%     [theta_vis, phi_vis] = ndgrid(-pi:pi/32:0.*pi, 0:2*pi/64:2*pi);
%     x_vis = cos(theta_vis);
%     y_vis = sin(theta_vis) .* cos(phi_vis);
%     z_vis = sin(theta_vis) .* sin(phi_vis);
%     n_vis = [x_vis(:), y_vis(:), z_vis(:)];
%     Y_vis = makeY(x_vis(:), y_vis(:), z_vis(:));
%     Yl_vis = Y_vis * l;
%     n_vis = n_vis .* repmat(Yl_vis, 1, 3);
%     surf(reshape(n_vis(:,1), size(x_vis)), ...
%          reshape(n_vis(:,2), size(y_vis)), ...
%          reshape(n_vis(:,3), size(z_vis)));
%     title(sprintf('lighting %d', iter)); axis equal;
%     xlabel('x');ylabel('y');zlabel('z');
    
    fprintf('lithting estimation finished in %.3fs\n', toc(t_light));
    
    %% estimate albedo
    t_albedo = tic;
    w_reg = 100.0;
    A_up = sparse(1:h*w, 1:h*w, Yl(:), h*w, h*w);
    A_reg = w_reg * mat_LoG;
    M_reg = spdiags(ones(num_pixels, 1), 0, num_pixels, num_pixels);
    A = [A_up(good_indices_1,good_indices_1); A_reg(good_indices_1,good_indices_1)];
    Br = [Ir(good_indices_1); LoG_ar(good_indices_1) * w_reg];
    ar_sub = (A'*A + 0.01*M_reg) \ (A'*Br);
    Bg = [Ig(good_indices_1); LoG_ag(good_indices_1) * w_reg];
    ag_sub = (A'*A + 0.01*M_reg) \ (A'*Bg);
    Bb = [Ib(good_indices_1); LoG_ab(good_indices_1) * w_reg];
    ab_sub = (A'*A + 0.01*M_reg) \ (A'*Bb);
    
    ar(good_indices_1) = ar_sub;
    ag(good_indices_1) = ag_sub;
    ab(good_indices_1) = ab_sub;
    
    albedo_map = zeros(h, w, 3);
    albedo_map(:,:,1) = ar; albedo_map(:,:,2) = ag; albedo_map(:,:,3) = ab;
%     figure;imshow(albedo_map);title('albedo');  

    fprintf('albedo estimation finished in %.3fs\n', toc(t_albedo));
    
    %% estimate geometry
    t_normal = tic;
    % nx = cos(theta), ny = sin(theta)*cos(phi), nz = sin(theta)*sin(phi)    
    for i=1:3
        theta = acos(nx);
        phi = atan2(nz, ny);
        
%         theta_mask = zeros(h, w);
%         theta_mask(valid_pixel_indices) = theta;
%         figure; imagesc(theta_mask); title('theta'); axis equal; colorbar;
%         phi_mask = zeros(h, w);
%         phi_mask(valid_pixel_indices) = phi;
%         figure; imagesc(phi_mask); title('phi'); axis equal; colorbar;
        
        % data term
        R_data = I_pixels - A_pixels .* repmat(Yl, 3, 1);
        
%         residue_mask = zeros(h, w);
%         Rmat = reshape(R, h*w, 3);
%         residue_mask(:) = sum(Rmat.*Rmat,2);
%         figure;imshow(residue_mask); title('residue'); axis equal; colorbar;
        
        % Jacobians
        % Y = [1, nx, ny, nz, nx*ny, nx*nz, ny*nz, nx*nx-ny*ny, 3*nz*nz-1]
        dnx_dtheta = -sin(theta); dnx_dphi = zeros(h*w, 1);
        dny_dtheta = cos(theta).*cos(phi); dny_dphi = -sin(theta).*sin(phi);
        dnz_dtheta = cos(theta).*sin(phi); dnz_dphi = sin(theta).*cos(phi);
        
        dY_dtheta = [zeros(h*w, 1), dnx_dtheta, dny_dtheta, dnz_dtheta, ...
            dnx_dtheta.*ny+nx.*dny_dtheta, ...
            dnx_dtheta.*nz+nx.*dnz_dtheta, ...
            dny_dtheta.*nz+ny.*dnz_dtheta, ...
            2*nx.*dnx_dtheta - 2 * ny.*dny_dtheta, ...
            6*nz.*dnz_dtheta];
        
        dY_dphi = [zeros(h*w, 1), dnx_dphi, dny_dphi, dnz_dphi, ...
            dnx_dphi.*ny+nx.*dny_dphi, ...
            dnx_dphi.*nz+nx.*dnz_dphi, ...
            dny_dphi.*nz+ny.*dnz_dphi, ...
            2*nx.*dnx_dphi - 2*ny.*dny_dphi, ...
            6*nz.*dnz_dphi];
        
        l_dY_dtheta = dY_dtheta*l;
        l_dY_dphi = dY_dphi*l;
        ar_vec = ar(:); ag_vec = ag(:); ab_vec = ab(:);
        
        Jr_theta = sparse(1:num_pixels, 1:num_pixels, -l_dY_dtheta(valid_pixel_indices).*ar_vec(valid_pixel_indices));
        Jr_phi = sparse(1:num_pixels, 1:num_pixels, -l_dY_dphi(valid_pixel_indices).*ar_vec(valid_pixel_indices));
        Jg_theta = sparse(1:num_pixels, 1:num_pixels, -l_dY_dtheta(valid_pixel_indices).*ag_vec(valid_pixel_indices));
        Jg_phi = sparse(1:num_pixels, 1:num_pixels, -l_dY_dphi(valid_pixel_indices).*ag_vec(valid_pixel_indices));
        Jb_theta = sparse(1:num_pixels, 1:num_pixels, -l_dY_dtheta(valid_pixel_indices).*ab_vec(valid_pixel_indices));
        Jb_phi = sparse(1:num_pixels, 1:num_pixels, -l_dY_dphi(valid_pixel_indices).*ab_vec(valid_pixel_indices));

        J_data = [Jr_theta, Jr_phi; ...
                  Jg_theta, Jg_phi; ...
                  Jb_theta, Jb_phi];
        
        % integrability term
        w_int = 1.0;
        nz_threshold = 1e-3;
        small_shift = 1e-5;
        nz_fixed = nz;
        small_nz_idx = find(abs(nz_fixed) < nz_threshold);
        nz_fixed(small_nz_idx) = sign(nz_fixed(small_nz_idx)) * nz_threshold;
        nx_over_nz = nx ./ (nz_fixed + small_shift);
        ny_over_nz = ny ./ (nz_fixed + small_shift);
        
        dnx_over_nz_dtheta = (nz .* dnx_dtheta - nx .* dnz_dtheta) ./ (nz .* nz + small_shift);
        dny_over_nz_dtheta = (nz .* dny_dtheta - ny .* dnz_dtheta) ./ (nz .* nz + small_shift);
        
        dnx_over_nz_dphi = (nz .* dnx_dphi - nx .* dnz_dphi) ./ (nz .* nz + small_shift);
        dny_over_nz_dphi = (nz .* dny_dphi - ny .* dnz_dphi) ./ (nz .* nz + small_shift);
        
        pixel_indices = reshape(1:h*w, h, w);
        pixel_indices_shift_up = circshift(pixel_indices, -1);    % -1
        pixel_indices_shift_right = circshift(pixel_indices, [0, 1]);   % -1
        v_pixel_indices = pixel_indices(:);
        v_pixel_indices_shift_up = pixel_indices_shift_up(:);
        v_pixel_indices_shift_right = pixel_indices_shift_right(:);
                
        C1 = sparse(1:h*w, v_pixel_indices, ones(h*w, 1)) - sparse(1:h*w, v_pixel_indices_shift_up, ones(h*w, 1));
        C2 = sparse(1:h*w, v_pixel_indices, ones(h*w, 1)) - sparse(1:h*w, v_pixel_indices_shift_right, ones(h*w, 1));
        
        R_int = (C1 * nx_over_nz - C2 * ny_over_nz) * w_int;
        
        bad_int_idx = abs(R_int)>1;
        R_int(bad_int_idx) = 0;

        J_int = [C1 * spdiags(dnx_over_nz_dtheta, 0, h*w, h*w) - C2 * spdiags(dny_over_nz_dtheta, 0, h*w, h*w), ...
                 C1 * spdiags(dnx_over_nz_dphi, 0, h*w, h*w) - C2 * spdiags(dny_over_nz_dphi, 0, h*w, h*w)];
        
        J_int = J_int(good_indices_1, good_indices_2) * w_int;
        
        % regularization term
        w_reg = 0.0;
        
        R_reg = mat_LoG * [nx0(:) - nx, ny0(:) - ny, nz0(:) - nz];
        R_reg = reshape(R_reg, [], 1);

        dRx_dtheta = -mat_LoG * spdiags(dnx_dtheta, 0, h*w, h*w);
        dRy_dtheta = -mat_LoG * spdiags(dny_dtheta, 0, h*w, h*w);
        dRz_dtheta = -mat_LoG * spdiags(dnz_dtheta, 0, h*w, h*w);

        Jx_theta = dRx_dtheta(valid_pixel_indices, valid_pixel_indices);
        Jy_theta = dRy_dtheta(valid_pixel_indices, valid_pixel_indices);
        Jz_theta = dRz_dtheta(valid_pixel_indices, valid_pixel_indices);
        
        dRx_dphi = -mat_LoG * spdiags(dnx_dphi, 0, h*w, h*w);
        dRy_dphi = -mat_LoG * spdiags(dny_dphi, 0, h*w, h*w);
        dRz_dphi = -mat_LoG * spdiags(dnz_dphi, 0, h*w, h*w);
        
        Jx_phi = dRx_dphi(valid_pixel_indices, valid_pixel_indices);
        Jy_phi = dRy_dphi(valid_pixel_indices, valid_pixel_indices);
        Jz_phi = dRz_dphi(valid_pixel_indices, valid_pixel_indices);
        
        J_reg = [Jx_theta, Jx_phi;
                 Jy_theta, Jy_phi;
                 Jz_theta, Jz_phi];
        J_reg = J_reg * w_reg;
        R_reg = R_reg * w_reg;
        
        % solve it
%         fprintf('solving for normal ...\n');
        w_lambda = 1.0 - 0.25 * (iter-1);
        M_reg = spdiags(ones(size(J_data, 2), 1), 0, size(J_data, 2), size(J_data, 2));
        J = [J_data; J_int; J_reg];
        R = [R_data(good_indices); ...
             R_int(good_indices_1); ...
             R_reg(good_indices)];
        JTJ = J' * J;
        JTR = J' * R;
        dx = (JTJ + w_lambda * M_reg) \ JTR;
        dx = max(-pi/3, min(pi/3, dx));
        
%         [Rcdf, xcenter] = hist(R); figure;plot(xcenter, Rcdf);title('R');
%         figure;plot(dx);title('dx');
%         [JJJR, xcenter] = hist(dx);figure;plot(xcenter, JJJR);title('hist dx');
        
        theta(good_indices_1) = theta(good_indices_1) - dx(1:num_pixels);
        phi(good_indices_1) = phi(good_indices_1) - dx(num_pixels+1:end);
%         fprintf('done.\n');
        
%         theta_mask = zeros(h, w);
%         theta_mask(valid_pixel_indices) = theta;
%         figure; imagesc(theta_mask); title('theta\_new'); axis equal; colorbar;
%         phi_mask = zeros(h, w);
%         phi_mask(valid_pixel_indices) = phi;
%         figure; imagesc(phi_mask); title('phi\_new'); axis equal; colorbar;
        nx = cos(theta); ny = sin(theta).*cos(phi); nz = sin(theta).*sin(phi);
        
%         Y = [ones(size(nx)), nx, ny, nz, nx.*ny, nx.*nz, ny.*nz, nx.*nx-ny.*ny, 3*nz.*nz-1];
%         Yl = Y * l;
%         lighting_mask = reshape(Yl, h, w);
%         figure;imagesc(lighting_mask); title('lighting\_new'); axis equal; colorbar; colormap gray;
    end
    fprintf('normal estimation finished in %.3fs\n', toc(t_normal));
    
    normal_map = zeros(h, w, 3);
    normal_map(:,:,1) = reshape(nx, h, w); 
    normal_map(:,:,2) = reshape(ny, h, w); 
    normal_map(:,:,3) = reshape(nz, h, w);
    normal_map = (normal_map + 1.0) * 0.5;
end

%% recover depth
[dh, dw, ~] = size(I_depth);

final_normal_map = imresize(normal_map, [dh, dw]);
depth0 = I_depth;



hfig = figure;
subplot(1, 4, 1); imshow(I_input); title('input');
subplot(1, 4, 2); imshow(albedo_map); title('albedo');
subplot(1, 4, 3); imshow(I_normal); title('normal');
subplot(1, 4, 4); imshow(normal_map); title('refined normal');
set(hfig, 'Position', [0 0 1200 480])

end

function Y = makeY(nx, ny, nz)
Y = [ones(size(nx)), nx, ny, nz, nx.*ny, nx.*nz, ny.*nz, nx.*nx-ny.*ny, 3*nz.*nz-1];
end