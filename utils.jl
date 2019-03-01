function bound2vert(b_min, b_max)
    dif = b_max - b_min
    dx = [dif[1], 0]
    dy = [0, dif[2]]

    v1 = b_min
    v2 = b_min + dx
    v3 = b_min + dx + dy
    v4 = b_min + dy
    v_lst = [v1, v2, v3, v4]
    return v_lst
end

function bound2dx(b_min, b_max)
    ndim = length(b_min)
    dif = b_max - b_min
    dx = Vector{Float64}[]
    for i in 1:ndim
        dx_ = [0.0 for n=1:ndim]
        dx_[i] = dif[i]*0.5
        push!(dx, dx_)
    end
    return dx
end


function whereami(q, b_min, b_max)
    ndim = length(q)
    idx = 1
    for n in 1:ndim
        tmp = (q[n] - b_min[n])/(b_max[n] - b_min[n])
        idx += (tmp>0.5)*2^(n-1)
    end
    return idx
end
