function [node_feats, edge_feats, node_weights, edge_weights] = ...
    randwalk_feats(RS, PS, G,  params, node_weights, edge_weights)
% Generate feature vectors from subgraphs centered on each graph node.
[n1, cr] = size(RS);
[n2, cp] = size(PS);
S = [RS zeros(n1, cp); zeros(n2, cr) PS];
node_count = n1 + n2;
code_count = cr + cp;
m = code_count * code_count;
[e1, e2] = find(G > 0);
edge_count = length(e1);
edge_type_count = length(params.edge_types);
edge_type_idx(params.edge_types) = 1 : edge_type_count;

% Computes random walk weights in each subgraph.
if ~exist('node_weights', 'var') || ~exist('edge_weights', 'var')
    [node_weights, edge_weights] = random_walk_weights(...
        G, params.subgraph_radius);
end

% For each node, finds the code words scored higher than threshold.
CI = cell(node_count, 1); 
for i = 1:n1
    CI{i} = find(RS(i, :) > params.code_score_thresh);
end
for i = n1 + 1 : n1 + n2
    CI{i} = find(PS(i - n1, :) > params.code_score_thresh) + cr;
end

% Computes edge scores. ES is #edge_count * #edge_codes.
a = sum(max(RS > params.code_score_thresh, [], 1));
b = sum(max(PS > params.code_score_thresh, [], 1));
c = max([a * b, a * a, b * b]);
row_idx = zeros(edge_count * c, 1);
col_idx = zeros(edge_count * c, 1);
edge_score = zeros(edge_count * c, 1);
ind = 0;
for i = 1 : edge_count
    ei = edge_type_idx(abs(G(e1(i), e2(i))));  
    [X, Y] = meshgrid(CI{e1(i)}, CI{e2(i)});
    Z = sub2ind([code_count, code_count], X(:), Y(:));
    idx = ind + [1 : length(Z)];
    col_idx(idx) = Z(:) + (ei - 1) * m;
    row_idx(idx) = ones(length(idx), 1) * i;
    edge_score(idx) = min(S(e1(i), X(:)), S(e2(i), Y(:)));
    ind = ind + length(idx);
end
if ind < length(row_idx)
    row_idx(ind + 1 : end) = [];
    col_idx(ind + 1 : end) = [];
    edge_score(ind + 1 : end) = [];
end
ES = sparse(row_idx, col_idx, edge_score, ...
    edge_count, m * edge_type_count);

% Generates feature vector for each subgraph.
node_feats = zeros(node_count, code_count);
row_idx = zeros(node_count * 3 * c, 1);
col_idx = row_idx; 
vals = row_idx;
ind = 0;
for i = 1:node_count
    flg = node_weights(i, :) > 0;
    if sum(flg) < 2
        continue;
    end
    node_feats(i, :) = weighted_pooling(...
        S(flg, :), node_weights(i, flg), params.pooling_mode);
    
    flg2 = edge_weights(i, :) > 0;
    if ~any(flg2)
        continue;
    end
    flg3 = sum(ES(flg2, :) > 0, 1) > 0;
    edge_feat = weighted_pooling(...
        ES(flg2, flg3), edge_weights(i, flg2), params.pooling_mode);
    
    Z = find(flg3);
    idx = ind + [1 : length(Z)]';
    while idx(end) > length(col_idx)
        col_idx = [col_idx; zeros((node_count - i) * 3 * c, 1)];
        row_idx = [row_idx; zeros((node_count - i) * 3 * c, 1)];
        vals = [vals; zeros((node_count - i) * 3 * c, 1)];
    end
    col_idx(idx) = Z(:);
    row_idx(idx) = ones(length(idx), 1) * i;
    vals(idx) = edge_feat;
    ind = ind + length(idx);
end
if ind < length(row_idx)
    row_idx(ind + 1 : end) = [];
    col_idx(ind + 1 : end) = [];
    vals(ind + 1 : end) = [];
end

edge_feats = sparse(row_idx, col_idx, vals, ...
    node_count, m * edge_type_count);
end

function f = weighted_pooling(feats, weights, mode)
% Performs weighted pooling over a set of features.
% Options for mode:
%     1:    max pooling.
%     2:    sum pooling (average pooling).
feats = bsxfun(@times, feats, weights(:));

if mode == 1
    f = max(feats, [], 1);
elseif mode == 2
    f = sum(feats, 1) / sum(weights);
end

end
