function val = sysprop(name)
%SYSPROP Java system property with a fallback for deployed (MCR) mode, where Java is unavailable.
% VAL = SYSPROP(NAME) returns the value of the Java system property NAME, e.g. 'user.home'.

if isdeployed
    switch name
        case 'user.home', val = getenv("HOME");
        case 'user.name', val = getenv("USER");
        otherwise,        val = getenv(upper(strrep(name, '.', '_')));
    end
else
    val = char(java.lang.System.getProperty(name));
end
