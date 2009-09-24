
def add_gem_library name

  s = "/opt/local/lib/ruby/gems/1.8/gems/" + name + "/lib/"

  $:.push s

end


