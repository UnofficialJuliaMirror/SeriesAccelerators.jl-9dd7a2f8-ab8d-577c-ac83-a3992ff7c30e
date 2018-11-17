const default_atol = eps()
const default_rtol = sqrt(eps())

"""
Check the convergence of series by comparing the new value to the
value of the series so far
"""
function check_convergence(x_new::T, x_old::T,
    rtol=default_rtol, atol=default_atol) where {T <: Number, N}
  @assert !isnan(x_new) && !isnan(x_old) "x_new = $x_new, x_old = $x_old"
  return isapprox(x_new, x_old, rtol=rtol, atol=atol)
end
function check_convergence(t_new::Array{T, N}, t_old::Array{T, N},
    rtol=default_rtol, atol=default_atol) where {T <: Number, N}
  @assert size(t_new) == size(t_old)
  @inbounds for i ∈ eachindex(t_new)
    !check_convergence(t_new[i], t_old[i], rtol, atol) && return false
  end
  return true
end

const default_initial_iterate = 5
const default_sum_limit = 1_000_000
const default_recursion = 1

function _seriesaccelerator(accelerator::T, series::U,
    recursion::Int, sum_limit::V, initial_iterate::W,
    rtol, atol) where {T<:Function, U<:Function, V<:Int, W<:Int}
  recursion = Int(min(initial_iterate - 1, recursion))
  old_value = series(initial_iterate) #accelerator(series, iterate, recursion)
  iterate = initial_iterate
  isconverged = false
  while !isconverged && iterate < sum_limit
    new_value = accelerator(series, recursion, iterate)
    isfinite(new_value) || break
    isconverged = check_convergence(new_value, old_value, rtol, atol)
    old_value = deepcopy(new_value)
    iterate += 1
  end
  return old_value, isconverged
end

function _memoise(f::T, data::Dict=Dict()) where {T<:Function}
  function fmemoised(i...)
    !haskey(data, i) && (data[i] = f(i...))
    return data[i]
  end
  return fmemoised, data
end

"""
Shanks transformation series accelerator.
https://en.wikipedia.org/wiki/Shanks_transformation

Arguments:
  series (optional, Function) : a function that accepts an argument, n::Int,
    and returns the nth value in the series
  sum_limit (optional, Int) : the value at which to stop the series
    (default is 1,000,000)
  rtol (optional, Number) : relative stopping tolerance
  atol (optional, Number) : absolute stopping tolerance
"""
function shanks(series::T,
    recursion::Int=default_recursion,
    sum_limit::U=default_sum_limit;
    rtol=default_rtol, atol=default_atol) where {T<:Function, U<:Int}
  @assert 0 <= recursion < sum_limit "$recursion, $sum_limit"
  memoisedseries, data = _memoise(series)
  sum_limit -= recursion # due to the way the shanks recursion changes the sum_limit
  f(n) = mapreduce(memoisedseries, +, 0:n)
  return _seriesaccelerator(_shanks, f, recursion, sum_limit,
    default_initial_iterate, rtol, atol)
end

function _shanks(f::T, recursion::Int, sum_limit::U) where {T<:Function, U<:Int}
  function _shanks_value(An1, An, An_1)
    denominator = ((An1 - An) - (An - An_1))
    iszero(denominator) && return An1 # then it's converged
    return An1 - (An1 - An)^2/denominator
  end
  if recursion == 0
    An1 = f(sum_limit + 1)
    An = f(sum_limit + 0)
    An_1 = f(sum_limit - 1)
    return _shanks_value(An1, An, An_1)
  else
    An1 = _shanks(f, recursion - 1, sum_limit + 1)
    An = _shanks(f, recursion - 1, sum_limit)
    An_1 = _shanks(f, recursion - 1, sum_limit - 1)
    return _shanks_value(An1, An, An_1)
  end
  throw("Shouldn't be able to reach here")
end

"""
van Wijngaarden transformation series accelerator.
https://en.wikipedia.org/wiki/Van_Wijngaarden_transformation

Arguments:
  series (optional, Function) : a function that accepts an argument, n::Int,
    and returns the nth value in the series
  sum_limit (optional, Int) : the value at which to stop the series
    (default is 1,000,000)
  rtol (optional, Number) : relative stopping tolerance
  atol (optional, Number) : absolute stopping tolerance
"""

function vanwijngaarden(series::T,
    recursion::Int=default_recursion,
    sum_limit::U=default_sum_limit;
    rtol=default_rtol, atol=default_atol) where {T<:Function, U<:Int}
  @assert 0 <= recursion "$recursion"
  @assert 0 < sum_limit "$sum_limit"
  memoisedseries, data = _memoise(series)
  return _seriesaccelerator(_vanwijngaarden, memoisedseries, recursion,
    sum_limit, default_initial_iterate, rtol, atol)
end

function _vanwijngaarden(f::T, recursion::V, sum_limit::U
    ) where {T<:Function, U<:Int, V<:Int}
  if recursion == 0
    return mapreduce(n -> f(n), +, 0:sum_limit)
  else
    return 0.5 * mapreduce(k -> _vanwijngaarden(f, recursion-1, k),
      +, [1, -1] .+ sum_limit)
  end
  throw("Shouldn't be able to reach here")
end

