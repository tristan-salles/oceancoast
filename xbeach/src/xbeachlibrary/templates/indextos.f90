!  DO NOT EDIT THIS FILE
!  But edit variable.f90 and scripts/generate.py
!  Compiling and running is taken care of by the Makefile

## helper functions
<%
def rank(var):
    """the number of dimensions"""
    return len(var["shape"])

def dimarray(var):
    """combinine the shape text into dimension"""
    parts = ["'%-20s'" % (dim,) for dim in var["shape"]]
    txt = "(/ {0} /)".format(",".join(parts))
    return txt

typecodes = {
 "double": "r",
 "character": "c",
 "int": "i"
}
%>
<%
def shape(var):
    # convert dims to strings
    dims = (str(dim) for dim in var["shape"])
    return ",".join(dims)
%>

%for i, var in enumerate(variables):
 case(  ${i+1})
   t%${typecodes[var["type"]]}${rank(var)}  => s%${var["name"]}
   t%rank =  ${rank(var)}
   t%type = '${typecodes[var["type"]]}'
   t%name = '${var["name"]}'
   t%btype = '${var["broadcast"]}'
   t%units= '${var["unit"]}'
   t%standardname= '${var.get("standard_name", "")}'
   t%description= '${var["description"]}'
%if rank(var) > 0:
   t%dimensions(1:${rank(var)}) = ${dimarray(var)}
%endif
%endfor

!directions for vi vim: filetype=fortran : syntax=fortran

