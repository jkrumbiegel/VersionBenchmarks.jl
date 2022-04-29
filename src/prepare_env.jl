_hide_output, specstring = ARGS
hide_output = parse(Bool, _hide_output)
using Pkg
Pkg.UPDATED_REGISTRY_THIS_SESSION[] = true # avoid updating every time
packages = eval(Meta.parse(specstring))
Pkg.add(packages; io = hide_output ? devnull : stdout)
Pkg.instantiate()
