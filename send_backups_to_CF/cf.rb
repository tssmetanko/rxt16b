#!/usr/bin/env ruby

require 'rubygems'
require 'fog'
require 'syslog'
require 'logger'
require 'getoptlong'
require 'date'
require 'thread'
#require 'rdoc/usage'

SEGMENT_LIMIT = 5368709119.0  # 5GB -1
BUFFER_SIZE = 1024 * 1024 * 10   # 1M
THREAD_COUNT=30

#SEGMENT_LIMIT = 1024 * 1024 *100 #100M
#BUFFER_SIZE = 1024 * 1024 * 10 #10M

$connection_settings={
	:provider => 'Rackspace',
	:rackspace_username=>ENV["CLOUDFILES_USERNAME"],
	:rackspace_api_key=>ENV["CLOUDFILES_APIKEY"],
	:rackspace_region=>:ord,
	:rackspace_auth_url  => 'https://identity.api.rackspacecloud.com/v2.0',
}

$LOG = Logger.new(STDOUT)
$debug=nil

class CF
  attr_accessor :container, :sync_mode, :retention_time;
  
  def connect(settings)
    @cf_connection=Fog::Storage.new($connection_settings)
    return @cf_connection
  #rescue ArgumentError
  #  $LOG.error("Is 'CLOUDFILES USERNAME' and 'CLOUDFILES API KEY' are set as system environment variables?" )
  rescue Exception => msg
     $LOG.error(msg.inspect) 
  end
  
  def set_default_container(container)
    @container=container
  end

  def set_container(container)
    @container=container
  end
  
  def list_objects(container=@container)
    pathes=@cf_connection.directories.get(container, option={:limit=>1000,})
    return pathes.files
  end

  def upload_file(path,objkey,container=@container)
    key=objkey.sub(/^\//,'')
    #Set object options aka headers
    #http://rubydoc.info/gems/fog/1.23.0/Fog/Storage/Rackspace/Real:put_object
    options=Hash.new
    #options['X-Delete-After']=@retention_time if @retention_time
    options['X-Delete-At']=@retention_time if @retention_time
        
    if @sync_mode then
      file_exists=nil
      #Just skeep existen files
      #cf_object=@cf_connection.directories.get(@container,option={:prefix=>key})
      #cf_size=cf_object.files.first.content_length unless cf_object.files.first.nil?
      if File.directory?(path) then
      #compare than names match when type is a direcrory
        file_exists=true unless @cf_connection.head_object(@container,key).nil? rescue Fog::Storage::Rackspace::NotFound
      else
      #compare than size of file in CF and file in local FS is equal.
        cf_size=@cf_connection.head_object(@container,key)[:headers]["Content-Length"] rescue Fog::Storage::Rackspace::NotFound
        fs_size=File.size(path)
        #puts "#{cf_size} #{fs_size}"
        if cf_size == fs_size.to_s then
          file_exists=true
        end
      end
      if file_exists
        $LOG.info("#{path} already exists")
        return
      end
    end

    unless File.directory?(path) then
      segments=Array.new
      large_file=nil
      object_key=nil
            
      large_file=true if File.size(path) > SEGMENT_LIMIT
      
      File.open(path) do |file|
        
        $LOG.debug("File #{path} opened") if $debug
        segment=0
        until file.eof? do
          offset=0
          if large_file then
            segment += 1
            segment_suffix=segment.to_s.rjust(10,"0")
            object_key="#{key}/#{segment_suffix}"
          else
            object_key=key
          end
          @cf_connection.put_object(@container,object_key,nil,options) do 
            if offset <= SEGMENT_LIMIT - BUFFER_SIZE then
              buf=file.read(BUFFER_SIZE).to_s
              offset += buf.size
              $LOG.debug("chunk with #{offset} of #{object_key} uploaded") if $debug
              buf
            else
              ''
            end
          end ? ($LOG.info("Put object #{object_key} to #{@container}")):()
          if large_file then
          #Get segment metadata and put it to segments array
          #Affected only for large files
            segment_head=@cf_connection.head_object(@container,object_key)[:headers]
            segments << {
                    :size_bytes=>segment_head["Content-Length"],
                    :etag=>segment_head["Etag"],
                    :path=>"#{@container}/#{object_key}"
            }
          end
        end
      end
      if large_file then
        #write static manifest for large file
        #Add header for static_large_object in case the object is a large object
        #http://rubydoc.info/gems/fog/1.23.0/Fog/Storage/Rackspace/Real:put_static_obj_manifest
        options['X-Static-Large-Object']="#{@container}/#{key}" if large_file==true
        @cf_connection.put_static_obj_manifest(@container,key,segments,options) ? ($LOG.info("Put file #{path} to #{@container}")):()
        #@cf_connection.put_object_manifest(@container,key.sub(/^\//,''),'X-Object-Manifest' => "#{@container}/#{key.sub(/^\//,'')}")
      end
    else
      #If Directory
      #Add header for directory in case the object is a directory
      options['Content-Type']="application/directory"
      @cf_connection.put_object(@container,key,nil,options)? ($LOG.info("Put directory #{path} to #{@container}")):()
    end
  rescue Exception => msg
    $LOG.error("error on #{path} #{msg.inspect}")
  end

  def upload_path(path,container_key=@container)

    threads=[]
    queue=Queue.new
    
    Thread.new(path) do |path| 
      upload=[path,path.rpartition("/").last]
      queue.push(upload)
    end
    
    #upload_file(path,path,container) #Just upload path, and no matter that this folder or file.
    if File.directory?(path) then #Also if path is folder, upload all contend of thise folder.
      Dir.chdir(path)
      Dir.glob("**/**") do |file|
        #cf_file_key="#{path}/#{file}"
        cf_file_key="#{path.rpartition("/").last}/#{file}"
        if File.readable?(file) then
          Thread.new(path) do |path|
            upload=[file,cf_file_key]
            queue.push(upload)
          end
        else
          $LOG.warn("The file #{file} not readable")
        end
      end
    end
    
    THREAD_COUNT.times do |count|
      threads << Thread.new(count) do |number|
        Thread.current[:number] = number
        while ! queue.empty? do
          begin
            upload = queue.pop
            #p upload
            upload_file(upload[0],upload[1])
          rescue Exception => err
            $LOG.error("Caught exception; exiting")
            $LOG.error(err)
            next
          end
        end
      end
    end
  
    threads.each do |thread|
      thread.join
    end    

  rescue Exception => msg
    $LOG.error(msg)
  end
  
  def list_all_objects(container=@container)
    i=0
    pathes=Array.new
    pathes_s=Array.new
    begin
      pathes_s.to_a.empty? ? (marker=''):(marker=pathes_s.to_a.last.key)
      pathes_s=@cf_connection.directories.get(container, option={:limit=>1000,:marker=>marker})
      pathes_s=pathes_s.files.map.to_a
      pathes << pathes_s
    end until pathes_s.empty?
    return pathes.flatten
  end

  #def object_info(object_path)
  #  container=@container
  #  @cf_connection.
  #end
  
  def list_containers()
    containers=@cf_connection.directories
    return containers
  end

  def list_backups(container=@container)
    backups=@cf_connection.directories.get(container,option={:delimiter=>"/",:limit=>1000})
    #backups=@cf_connection.get_container(container,options={:delimiter=>"/",:limit=>1000})
    #p backups.files
    return backups.files
  end
  
  def list_backup_content(backup)
    i=0
    pathes=Array.new
    pathes_s=Array.new
    begin
      pathes_s.to_a.empty? ? (marker=''):(marker=pathes_s.to_a.last.key)
      pathes_s=@cf_connection.directories.get(@container,option={:limit=>1000,:prefix=>"#{backup}/BKP",:marker=>marker})
      pathes_s=pathes_s.files.map.to_a
      pathes << pathes_s
    end until pathes_s.empty?
    return pathes.flatten
  end

  def info(key)
    #cf_object=@cf_connection.directories.get(@container,option={:prefix=>key.sub(/^\//,'')})
    #p cf_object.files.first.head unless cf_object.files.first.nil?
    #puts cf_object
    cf_object_head=@cf_connection.head_object(@container,key.sub(/^\//,'')).headers
    return cf_object_head
  end

  def delete_object(object)
    object.destroy ? ( $LOG.info("#{object.key} was deleted")) : ($LOG.error("ERROR on #{object.key}" ))
    #$LOG.info("#{object.key} deleted")
  end
  
  def delete_objects(objects)
  #theated destroing
    threads=[]
    queue=Queue.new

    objects.each do |pathobj|
      unless pathobj.key.nil? then
        Thread.new(pathobj) do |object|
          queue.push(object)
        end
      end
    end

    THREAD_COUNT.times do |count|
      threads << Thread.new(count) do |number|
        Thread.current[:number] = number
        while ! queue.empty? do
          begin
            object = queue.pop
            delete_object(object)
          rescue Exception => err
            $LOG.error("Caught exception; exiting")
            $LOG.error(err)
            next
          end
        end
      end
    end

    threads.each do |thread|
      thread.join
    end
  end
  
  def older_than(objects,rm_date=7)
  #Select objects older than date
    oldest_objects=Array.new
    objects.each do |object|
      creation_time=(/(\w+)\/BKP-(\d+-\d+)(?:\/.*)?/.match object.key)[2]
      if ((Time.now - Time.strptime(creation_time, "%d%m%y-%M%M")) > rm_date.to_i*3600*24) then
        oldest_objects << object
      end
    end
    return oldest_objects
  end
  
end

class RetentionTime
  def self.str_to_timestamp(retention_time)
    case retention_time[-1]
      when "d"
        return 24*60*60*retention_time[0...-1].to_i+Time.now.to_i
      when "h"
        return 60*60*retention_time[0...-1].to_i+Time.now.to_i
      when "m"
        return 60*retention_time[0...-1].to_i+Time.now.to_i
      else
        return retention_time.to_i
    end    
  end  
end

#Processing options
options=GetoptLong.new(
  ['--help','-h', GetoptLong::NO_ARGUMENT],
  ['--debug','-d', GetoptLong::NO_ARGUMENT],
  ['--container-name','-c', GetoptLong::REQUIRED_ARGUMENT],
  ['--older-than','-o', GetoptLong::REQUIRED_ARGUMENT],
  ['--sync','-s', GetoptLong::NO_ARGUMENT],
  ['--retention-time','-r',GetoptLong::REQUIRED_ARGUMENT],
)
older_than=nil
retention_time=nil
container=nil
sync=nil

options.each do |opt, arg|
  case opt
    when '--help'
      puts 'help'
    when '--container-name'
      container=arg
      RDoc::usage if container.empty? || container.nil?
    when '--older-than'
      older_than=arg
    when '--sync'
      sync=true
    when '--debug'
      $debug=true
    when '--retention-time'
      retention_time=arg
  end
end

cf=CF.new
cf.connect($connection_settings)
cf.retention_time=RetentionTime.str_to_timestamp(retention_time) if retention_time

case ARGV[0]
  when "list"
    if ARGV[1].nil? then 
      cf.list_containers.each do |container|
        puts container.key
      end
    else
      cf.list_all_objects(ARGV[1]).each do |object|
        puts object.key
      end
    end
  when "upload"
    if (ARGV[2].nil?) and (!ARGV[1].nil?) then
      cf.upload_path(ARGV[1])
    else
      cf.container = (ARGV[1])
      cf.sync_mode = true if sync==true
      cf.upload_path(ARGV[2])
    end
  when "remove_backups"
    unless ARGV[1].nil? and ARGV[2].nil? then
      older_than=7 if older_than.nil?
      cf.container=(ARGV[1])
      #cf.older_than(cf.list_backup_content(ARGV[2]),older_than).each do |object|
      #  puts object.key
      #end
      older_than.nil? ? (rm_list=cf.list_backup_content(ARGV[2])):(rm_list=cf.older_than(cf.list_backup_content(ARGV[2]),older_than))
      cf.delete_objects(rm_list)
    else
      'hm 00001'
    end
  when "list_backups"
    if not ARGV[1].nil? and ARGV[2].nil? then
      #set only name of backup
      cf.container=(ARGV[1])
      cf.list_backups.map.each do |backup|
        puts backup.key unless backup.key.nil?
      end
    elsif (not ARGV[1].nil?) and ( not ARGV[2].nil?)
      #set name of backup
      cf.container=(ARGV[1])
      older_than.nil? ? (list = cf.list_backup_content(ARGV[2])):(list=cf.older_than(cf.list_backup_content(ARGV[2]),older_than))
      list.each do |backup| 
        puts backup.key unless backup.key.nil?
      end
    end
  when "clean"
    unless ARGV[1].nil? and ARGV[1].empty?
      #cf.container=ARGV[1]
      cf.delete_objects(cf.list_all_objects(ARGV[1]))
      #p cf.list_all_objects(ARGV[1])
    end
  when "info"
    if (ARGV[2].nil?) and (!ARGV[1].nil?) then
      header=cf.info(ARGV[1])
    else
      cf.container=(ARGV[1])
      header=cf.info(ARGV[2])
    end
    header.each do |head, value|
      puts "#{head} => #{value}"  
    end
  when "download"
    'download'
  else
    puts "Something went wrong... :-) "
end

