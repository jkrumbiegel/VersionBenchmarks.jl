@vbtime "using Colors" begin
    using Colors
end

function rgbatuple(c::Colorant)
    rgba = RGBA(c)
    return (red(rgba), green(rgba), blue(rgba), alpha(rgba))
end

@vbtime "Call function" begin
    rgbatuple(HSV(0.1, 0.2, 0.3))
end
