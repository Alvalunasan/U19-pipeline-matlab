%{
# pointer for a pre-saved set of parameter values
-> imaging.McMethod
mc_parameter_set_id:   int    # parameter set id
%}

classdef McParameterSet < dj.Manual
    methods
        function insert(self, key)
            
            insert@dj.Manual(self, key);
            make(imaging.McParameterSetParameter, key)
        end
    end
end
