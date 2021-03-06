%MAP_MCNN   Translate .mat to density map.
%   map_mcnn(file_path) returns none
%  
%   default parameters
%     img_path:  'UAVData/train_data/train_img'
%     gt_path:   'UAVData/train_data/ground_truth'
%     save_path: 'UAVData/train_data/train_gt'
%     scale:     [-1, -1] represent for not resize, eg. [480, 640] is height
%     -> 480 and width->640
%     type:     'MCNN' ('P2P')
%     peoples:  1 represent for 1 point is how many peoples
%
%   Folder arragement
%     UAVData
%     ├── test_data
%     │   ├── ground_truth
%     │   ├── test_gt
%     │   └── test_img
%     └── train_data
%         ├── ground_truth
%         │   ├── GT_IMG_1.mat
%         │   └── GT_IMG_2.mat
%         ├── train_gt
%         └── train_img
%             ├── IMG_1.jpg
%             └── IMG_2.jpg

%   Example:
%     map_mcnn('img_path', 'UAVData/train_data/train_img', 'gt_path', 'UAVData/train_data/ground_truth', 'save_path', 'UAVData/train_data/train_gt', 'scale', [-1, -1], 'peoples', 1)

%   Copyright Ling Bao.
%   July 12, 2017
function map_mcnn(varargin)
    % 默认参数设置
    ip = inputParser;
    ip.addParameter('img_path', 'UAVData/train_data/train_img');
    ip.addParameter('gt_path', 'UAVData/train_data/ground_truth');
    ip.addParameter('save_path', 'UAVData/train_data/train_gt');
    ip.addParameter('scale', [-1, -1]);
    ip.addParameter('type', 'MCNN');
    ip.addParameter('peoples', 1);
    
    % 参数解析
    ip.parse(varargin{:});
    results = ip.Results;
    img_path0 = results.img_path;
    gt_path0 = results.gt_path;
    save_path0 = results.save_path;
    scale = results.scale;
    type = results.type;
    peoples = results.peoples;

    % 获取待处理的图片列表
    file_path = dir([img_path0, '/*.jpg']);
    for i = 1 : length(file_path)
        % 图片/密度预标签名
        filename = split(file_path(i).name, '.');
        name = filename(1);

        % 获取图片/密度预标签路径以及保存路径
        img_path = sprintf('%s%s%s%s', img_path0, '/', name, '.jpg');
        gt_path = sprintf('%s%s%s%s', gt_path0, '/', name, '.mat');
        save_path = sprintf('%s%s%s%s', save_path0, '/', name, '.mat');
        
        % 读取图片/密度预标签
        image = imread(img_path);
        try 
            I = rgb2gray(image);
        catch
            I=image;
        end
        load(gt_path);
        location = image_info{1}.location; % 获取标定的人头坐标
        gt = ceil(location);
        
        % 清除无效坐标
        gtsize = size(gt, 1);
        tmpgt = gt; % 中间变量，便于操作
        numofdel = 0; % 删除的个数，用于矫正索引
        for j = 1 : gtsize
            if gt(j, 1)<=0 || gt(i, 2)<=0 || gt(j,1)>size(image ,2)...
                    || gt(j, 2)>size(image, 1)
                tmpgt(j - numofdel, :) = []; % 索引需要矫正
                numofdel = numofdel + 1;
            end
        end
        gt = tmpgt;
        
        % 根据参数判断是否进行缩放
        if scale(1) <= 0 || scale(2) <= 0
            image_size = size(image);
            scale(1) = image_size(1);
            scale(2) = image_size(2);
        end
        
        % 进行等比例缩放，不足部分将以0填充
        i_scale = size(I, 1) / scale(1);
        j_scale = size(I, 2) / scale(2); % 判断行列的缩放比
        if i_scale > j_scale
            ratio = i_scale;
        else
            ratio = j_scale;
        end
        
        I = imresize(I, round(size(I) / ratio));
        gt = ceil(gt / ratio);

        outputimage = uint8(zeros(scale(1),  scale(2)));
        outputimage(1:size(I, 1), 1:size(I, 2), :) = outputimage(1:size(I, 1), 1:size(I, 2), :) + I;
        I = outputimage;
        
        % 对图片和密度图均等比例缩小4倍，用于匹配MCNN池化后的标签尺寸要求，而P2P则不需要
        if type == 'MCNN'
            I = imresize(outputimage, ceil(size(outputimage) / 4)); % 尺寸大小除以4
            gt = ceil(gt / 4); % 对应人头坐标除以4并上取整，同样是为了匹配MCNN池化
        end
        
        % 生成一个等大的0矩阵，gt和标定的gt矩阵遍历比较，得到一个二值矩阵
        D = zeros(size(I));
        for k =1:size(gt, 1)
          if gt(k,2)>0 && gt(k, 1)>0
              D(gt(k, 2), gt(k, 1)) = 1; % 此矩阵为生成的二值矩阵
          end
        end
        
        % 求人头数
        Headnum = 0;
        for m = 1:size(D, 1)
            for n = 1:size(D, 2)
                if D(m, n) == 1
                    Headnum = Headnum + 1;
                end
            end
        end
        
        % 根据距离情况确定人头半径
        Distance = zeros(size(D, 1), size(D, 2)); % 距离矩阵
        for p = 1:size(D,1)
            for q = 1:size(D, 2)
                if D(p, q)==1
                    for radius = 1:500
                    SearchHeads = searchhead(D, p, q, radius); % 搜索半径递增
                    if size(SearchHeads, 1) > 7 % 直到搜索到8个人头(包括本身）
                       for r =1:size(SearchHeads, 1)
                           Distance(p, q) = Distance(p, q) + distance(p, q, SearchHeads(r, 1), SearchHeads(r, 2));
                       end
                       Distance(p, q) = (1 / (size(SearchHeads, 1) - 1)) * Distance(p, q);
                       break
                    end
                    end
                end
            end
        end
        
        m = size(I, 1);
        n = size(I, 2);
        d_map = zeros(ceil(m), ceil(n));
        
        % 生成密度图
        for j = 1 : size(gt, 1)
            ksize = Distance(gt(j, 2),(gt(j, 1)));

            ksize = max(ksize,20);
            ksize = min(ksize,40);
            ksize = ceil(ksize);
            radius = ceil(ksize/2);
            sigma = 0.3*ksize;
            x_ = max(1,min(n,floor(gt(j, 1))));
            y_ = max(1,min(m,floor(gt(j, 2))));
            h = fspecial('gaussian', ksize, sigma);

            hsize = size(h);
            hend = hsize(2);
            b = 0;

            if (x_ - radius + 1 < 1)
               for ra = 0 : radius - x_ -1
                   h(:, hend - ra) = h(:, hend - ra) + h(:, 1);
                   h(:, 1) = [];
               end
            end

            if (x_ + ksize - radius > n)
               for ra = 0 : x_ + ksize - radius -n-1
                   h(:, 1 + ra) = h(:, 1 + ra) + h(:, size(h,2));
                   h(:, size(h,2)) = [];
               end
            end

            if (y_ - radius + 1 < 1)
               for ra = 0 : radius - y_ -1
                   h(hend - ra,:) = h(hend - ra,:) + h(1,:);
                   h(1,:) = [];
               end
            end

            if (y_ + ksize -radius > m)
               for ra = 0 : y_ + ksize - radius - m-1
                  h(1 + ra, :) = h(1 + ra, :) + h(size(h,1), :);
                  h(size(h,1), :) = [];
               end
            end

            d_map(max(y_-radius+1,1):min(y_+ksize-radius,m),max(x_-radius+1,1):min(x_+ksize-radius,n))...
                 = d_map(max(y_-radius+1,1):min(y_+ksize-radius,m),max(x_-radius+1,1):min(x_+ksize-radius,n))...
                  + h;
        end
        
        d_map = d_map * peoples;
        
        % 绘图显示
        count = ceil(sum(sum(d_map))) % 人数
        subplot(121)
        contour(d_map)
        axis ij
        subplot(122)
        contour(D)
        axis ij
        display(['saved:', num2str(i)]);
        
        % 数据保存
        outputD_map=zeros(size(D, 1), size(D, 2));
        outputD_map(1:size(d_map, 1), 1:size(d_map, 2)) = outputD_map(1:size(d_map, 1), 1:size(d_map, 2)) + d_map;
        save(save_path, 'outputD_map');
    end
end