# using GridLayoutBase
@timed using GridLayoutBase

# GridLayout constructor
@timed GridLayout()

# Big GridLayout
@timed let
    gl = GridLayout()
    for i in 1:10, j in 1:10, k in 1:10
        gl[i, j] = GridLayout()
    end
end
