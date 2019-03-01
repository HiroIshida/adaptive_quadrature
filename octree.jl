using LinearAlgebra
using Interpolations
using SpecialFunctions
using PyPlot
import Base: show
include("utils.jl")

mutable struct Node
    id::Int
    b_min
    b_max
    id_child::Union{Vector{Int}, Nothing}
    itp # type?
    function Node(id, b_min, b_max)
        new(id, b_min, b_max, nothing, nothing)
    end
end

mutable struct Tree
    N::Int
    node::Vector{Node}
    node_root::Node
    function Tree(b_min, b_max)
        id_node = 1
        node_root = Node(id_node, b_min, b_max)
        new(1, [node_root], node_root)
    end
end

function split!(tree::Tree, node::Node)
    # edit node
    leaves = [1, 2, 3, 4] .+ tree.N
    node.id_child = leaves

    # edit tree
    b_min = node.b_min
    b_max = node.b_max
    dif = b_max - b_min
    dx = [dif[1]*0.5, 0]
    dy = [0, dif[2]*0.5]
    b_center = b_min .+ dx .+ dy

    for j in 0:1, i in 0:1#, k in 0:1
        add = (i%2)*dx + (j%2)*dy 
        node_new = Node(tree.N+1, b_min+add, b_center+add)
        push!(tree.node, node_new)
        tree.N += 1
    end
end

function needSplitting(node::Node, f)
    v_lst = bound2vert(node.b_min, node.b_max)
    f_lst = [f(v) for v in v_lst]

    data = [f_lst[1] f_lst[4]; f_lst[2] f_lst[3]]
    itp = interpolate(data, BSpline(Linear()))

    center_itp = itp(1.5, 1.5) # note: interp starts from 1 
    center_real = f(0.5*(node.b_max + node.b_min))

    error = abs(center_itp - center_real)
    #println(error)

    return ~(error<0.02) 
end

function auto_split!(tree::Tree, f) # recursive way
    # in the laef, we must add itp
    function recursion(node::Node)
        if needSplitting(node, f)
            split!(tree, node)
            for id in node.id_child
                recursion(tree.node[id])
            end
        else  # if the node is the final decendent, we endow itp to them
            b_min = node.b_min
            b_max = node.b_max
            v_lst = bound2vert(b_min, b_max)
            f_lst = [f(v) for v in v_lst]
            data = [f_lst[1] f_lst[4]; f_lst[2] f_lst[3]]
            itp_ = interpolate(data, BSpline(Linear())) # this raw itp object is useless as it is now

            node.itp = function itp(p)
                p_modif = (p - b_min)./(b_max - b_min) .+ 1
                return itp_(p_modif[1], p_modif[2])
            end

        end
    end
    recursion(tree.node_root)
    println("finish autosplit")
end

function show(tree::Tree)
    function recursion(node::Node)
        if node.id_child!=nothing
            for id in node.id_child
                recursion(tree.node[id])
            end
        else
            show(node; color=:r)
            sleep(0.01)
        end
    end
    recursion(tree.node_root)
    println("finish show")
end

function search_idx(tree::Tree, q)
    node = tree.node_root
    while(true)
        if node.id_child == nothing
            return node.id
        end
        idx = whereami(q, node.b_min, node.b_max)
        id_next = node.id_child[idx]
        node = tree.node[id_next]
    end
end

function evaluate(tree::Tree, q)
    id = search_idx(tree, q)
    node = tree.node[id]
    return node.itp(q)
end



sigma = 8
f(x) = 0.5*(1 + erf((-norm(x)+40)/sqrt(2*sigma^2)))
t = Tree([-100, -100], [100, 100])
auto_split!(t, f)

q = [60, 0]
println(evaluate(t, q))

#=
function main1()
    sigma = 6
    f(x) = 1/sqrt(2*pi*sigma^2)*exp(-(norm(x)-30)^2/(2*sigma^2))
    x_start = 60
    v_lst = bound2vert([x_start, x_start], [x_start + 5, x_start + 5])
    f_lst = [f(v) for v in v_lst]
    data = [f_lst[1] f_lst[4]; f_lst[2] f_lst[3]]
    println(data)
    itp = interpolate(data, BSpline(Linear()))
    println(itp(1.5, 1.5))
    println(f([x_start + 2.5, x_start + 2.5]))
    v = itp(1.5, 1.5) - f([x_start + 2.5, x_start + 2.5])
    println(v)
end
main1()
=#
                  





    

