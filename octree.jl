using LinearAlgebra
import Interpolations
using SpecialFunctions
using PyPlot
using Test
import Base: show

push!(LOAD_PATH, "./NearestNeighbors.jl")
using NearestNeighbors
include("utils.jl")

const Vertex = Vector{Float64}

mutable struct Node
    id::Int
    ndim::Int
    b_min
    b_max
    id_vert::Vector{Int}
    id_child::Union{Vector{Int}, Nothing}
    itp # type?
    function Node(id, b_min, b_max, id_vert)
        ndim = length(b_min)
        new(id, ndim, b_min, b_max, id_vert, nothing, nothing)
    end
end

function show(node::Node; color=:r)
    v_lst = bound2vert(node.b_min, node.b_max)
    if node.ndim == 2
        lst_pair = [[1, 2], [2, 4], [4, 3], [3, 1]]
        for pair in lst_pair 
            idx1 = pair[1]; idx2 = pair[2]
            x = [v_lst[idx1][1], v_lst[idx2][1]]
            y = [v_lst[idx1][2], v_lst[idx2][2]]
            PyPlot.plot(x, y, color)
        end
    elseif node.ndim == 3
        lst_pair = [[1, 3], [3, 4], [4, 2], [2, 1], 
                    [1, 5], [2, 6], [4, 8], [3, 7],
                    [5, 7], [7, 8], [8, 6], [6, 5]]
        for pair in lst_pair 
            idx1 = pair[1]; idx2 = pair[2]
            x = [v_lst[idx1][1], v_lst[idx2][1]]
            y = [v_lst[idx1][2], v_lst[idx2][2]]
            z = [v_lst[idx1][3], v_lst[idx2][3]]
            PyPlot.plot3D(x, y, z, color)
        end
    else
        error("is not supported")
    end

end

mutable struct Tree
    # member variable
    N_node::Int
    N_vert::Int
    ndim::Int
    node::Vector{Node}
    node_root::Node
    vertex::Vector{Vertex}
    data::Vector{Float64} # data stored in vertex
    func#function

    function Tree(b_min, b_max, func)
        N_node = 1
        N_vert = 4
        ndim = length(b_min)
        v_lst = bound2vert(b_min, b_max)
        f_lst = [func(v) for v in v_lst]
        id_vert = [i for i in 1:2^ndim]
        node_root = Node(N_node, b_min, b_max, id_vert)
        new(N_node, N_vert, ndim, [node_root], node_root, v_lst, f_lst, func)
    end
end

function split!(tree::Tree, node::Node)
    # id of new node 
    id_child = [i for i in 1:2^(tree.ndim)] .+ tree.N_node
    node.id_child = id_child

    # generate new nodes
    b_min = node.b_min
    b_max = node.b_max
    dif = b_max - b_min
    dx = bound2dx(b_min, b_max)*0.5
    b_center = (b_min + b_max)*0.5

    for i in 0:2^tree.ndim-1
        add = [0.0 for n in 1:tree.ndim]
        for dim in 1:tree.ndim
            if mod(div(i, 2^(dim-1)), 2) == 1
                add += dx[dim]
            end
        end

        # edit new node and corresponding vertex in tree
        id_new = tree.N_node+1
        b_min_new = b_min+add
        b_max_new = b_center+add # not b_max + add
        vertices_new = bound2vert(b_min_new, b_max_new)

        ## dangerous: complicated and potentially buggy
        for v in vertices_new
            push!(tree.vertex, v)
            push!(tree.data, tree.func(v))
        end
        id_vert = [tree.N_vert + i for i in 1:2^tree.ndim]
        node_new = Node(tree.N_node+1, b_min_new, b_max_new, id_vert)
        push!(tree.node, node_new)
        tree.N_vert += 2^tree.ndim
        tree.N_node += 1
        ## dangerous
    end
end


function auto_split!(tree::Tree, predicate) 
    # recusive split based on the boolean returned by predicate
    # perdicate: Node →  bool
    # interpolation objecet is endowed with each terminal nodes hh
    function recursion(node::Node)
        if predicate(node)
            split!(tree, node)
            for id in node.id_child
                recursion(tree.node[id])
            end
        else  # if terminal node
            b_min = node.b_min
            b_max = node.b_max
            v_lst = bound2vert(b_min, b_max)
            f_lst = [tree.func(v) for v in v_lst]
            data = form_data_cubic(f_lst, tree.ndim)
            itp_ = interpolate(data, BSpline(Linear())) 

            function itp(p)
                p_modif = (p - b_min)./(b_max - b_min) .+ 1
                return (tree.ndim == 2 ? itp_(p_modif[1], p_modif[2]) :
                        itp_(p_modif[1], p_modif[2], p_modif[3]))
            end
            node.itp = itp
        end
    end
    recursion(tree.node_root)
    println("finish autosplit")
end

function vertex_reduction!(tree::Tree)
    println("start vertex reductoin")

    # build kdtree
    vert_mat = zeros(tree.ndim, tree.N_vert)
    for n in 1:tree.N_vert
        if tree.ndim == 2
            vert_mat[:, n] = [tree.vertex[n][1], tree.vertex[n][2]]
        elseif tree.ndim == 3
            vert_mat[:, n] = [tree.vertex[n][1], tree.vertex[n][2], tree.vertex[n][3]]
        end
    end
    kdtree = KDTree(vert_mat, leafsize=20)

    # first re-label the indices.
    # for example if S1 = [1, 4, 6], S2 = [2, 3, 7], S3 =[5, 8] are duplicated
    # label them i1=1 i2=2 i3=3. Then, make a map from S -> i
    # potentially dangerous operation
    vertex_new = Vertex[]
    data_new = Float64[]
    id_lst = [i for i in 1:tree.N_vert]
    map = [-1 for i in 1:tree.N_vert] # -1 represetnts unvisited
    ε = 1e-4
    id_new = 1
    while(length(id_lst)>0)
        id = id_lst[1] # pop
        id_lst = setdiff(id_lst, id)
        map[id] = id_new
        push!(vertex_new, tree.vertex[id])
        push!(data_new, tree.data[id])
        id_depuli_lst = inrange(kdtree, tree.vertex[id], ε, true)
        for id_depuli in id_depuli_lst
            map[id_depuli] = id_new
            id_lst = setdiff(id_lst, id_depuli)
        end
        id_new += 1
    end
    tree.N_vert = length(vertex_new)
    tree.vertex = vertex_new
    tree.data = data_new

    function recursion(node::Node)
        if node.id_child!=nothing
            for id in node.id_child
                recursion(tree.node[id])
            end
        else
            node.id_vert = [map[i] for i in node.id_vert]
        end
    end
    recursion(tree.node_root)
    println("end vertex reduction")
end

function show(tree::Tree)
    function recursion(node::Node)
        if node.id_child!=nothing
            for id in node.id_child
                recursion(tree.node[id])
            end
        else
            show(node; color=:r)
        end
    end
    recursion(tree.node_root)
    println("finish show")
end

function evaluate(tree::Tree, q)
    node = tree.node_root
    while(true)
        if node.id_child == nothing
            data_itp = form_data_cubic(tree.data[node.id_vert], tree.ndim)
            itp = interpolate(data_itp, BSpline(Linear())) #raw
            q_modif = (q - node.b_min)./(node.b_max - node.b_min) .+ 1
            if tree.ndim == 2
                return itp(q_modif[1], q_modif[2])
            elseif tree.ndim == 3
                return itp(q_modif[1], q_modif[2], q_modif[3])
            else
                error("not supported")
            end
        end
        idx = whereami(q, node.b_min, node.b_max)
        id_next = node.id_child[idx]
        node = tree.node[id_next]
    end
end

function evaluate_(tree::Tree, q)
    node = tree.node_root
    while(true)
        node.id_child == nothing && return node.itp(q)
        idx = whereami(q, node.b_min, node.b_max)
        id_next = node.id_child[idx]
        node = tree.node[id_next]
    end
end


function pred_standard(node::Node, f, ε, n_grid, itp_method)
    # choose interpolation method: itp_method
    # curretnly available methods are "Linear()" and "Constant()"
    # apparently, if you choose "Constant", much more cells are required.
    
    ndim = node.ndim
    v_lst = bound2vert(node.b_min, node.b_max)
    f_lst = [f(v) for v in v_lst]
    data = form_data_cubic(f_lst, ndim)
    itp = interpolate(data, BSpline(itp_method))

    # evaluate the interpolation error for many points in the cell 
    # and only care about maximum error 
    points_eval = grid_points(n_grid, node.b_min, node.b_max)
    max_error = -Inf
    for p in points_eval
        p_reg = (p - node.b_min)./(node.b_max - node.b_min) .+ 1
        val_itp = (ndim == 2 ? itp(p_reg[1], p_reg[2]) : itp(p_reg[1], p_reg[2], p_reg[3]))
        val_real = f(p)
        error = abs(val_real - val_itp)
        if max_error < error
            max_error = error
        end
    end
    return ~(max_error<ε)
end

