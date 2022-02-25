@vbtime "using GridLayoutBase" begin
    using GridLayoutBase
end

@vbtime "GridLayout constructor" begin
    GridLayout()
end

@vbtime "Big GridLayout" let
    gl = GridLayout()
    for i in 1:10, j in 1:10, k in 1:10
        gl[i, j] = GridLayout()
    end
end
