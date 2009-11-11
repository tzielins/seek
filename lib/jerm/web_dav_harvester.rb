
require 'jerm/harvester'
require 'jerm/web_dav'

class WebDavHarvester < Harvester

  include WebDav
  
  def initialize username,password,base_uri
    @username=username
    @password=password
    @base_uri=base_uri
  end

  def authenticate
    raise Exception.new("No username") if @username.nil?
    raise Exception.new("No password") if @password.nil?
  end

  def changed_since time
    trees = get_contents URI.parse(@base_uri),@username,@password,true
    puts "-- #{trees.size} --"
    #need to split tree into a list of the final directory leaves
    items = []
    trees.each do |tree|
      items = items + split_tree(tree)
    end
    
    return items
  end

  def split_tree tree
    items = []
    if !tree[:children].empty? && tree[:children][0][:is_directory]
      tree[:children].each {|i| items = items + split_tree(i)}
    else
      items << tree unless tree[:children].empty?
    end
    return items
  end
  
end
