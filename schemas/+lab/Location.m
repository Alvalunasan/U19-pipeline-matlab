%{
# The physical location at which an session is performed or appliances are located.
# This could be a room, a rig or a bench.
location:                   varchar(32)
-----
location_description='':    varchar(255)
%}

classdef Location < dj.Lookup
    properties
    end
end