require 'rubygems'
require 'flacinfo'
require 'mp3info'
require 'fileutils'

FLACDIR = "flac/"
MP3MIRROR = "mp3mirror/"
LAMEOPTS = [ "-V2", "--quiet" ] 

#yawn, constants, la la la
def tag_mapping
{
	#however mp3info maps the 1st 4
	"ALBUM" => "album", #:TALB,
	"TITLE" => "title", #:TIT2,
	"ARTIST" => "artist", #:TPE1,
	#Argh! This must be an int.
	"TRACKNUMBER" => "tracknum", #:TRCK,
}
end

def shell_escape(str)
	escaped = str.gsub('"',%q(\"))
	ans = '"' + escaped + '"'
	sanity = `echo #{ans}`.chomp
	raise "escape issue: \n#{str}\n#{sanity}\n#{ans}" unless str == sanity
	return ans
end

#work begins here!
albums = FileList["#{FLACDIR}/**/"]

#This is the transcodify bit:
albums.each do |album|
	albummp3prep = album + "!mp3prep"

	#Make a task for making the tasks of mp3mirroring
	#this way we don't need to search for every last file on starup
	task albummp3prep do
		flacs = FileList["#{album}/*.flac"]
		next if flacs.size == 0
		
		info = album + "!info"
		task info do
			puts( "\nWorking on #{album}\n\n"  )
		end
		
		task album => info

		mp3albumdir = album.sub( FLACDIR, MP3MIRROR )
		directory mp3albumdir
		task album => mp3albumdir

		#maybe we made a mess last time?
		failures = FileList["#{mp3albumdir}/*.xmp3"]
		failures.each do |failure|
			task failure do
				File.delete( failure )
			end
			task album=>failure
		end

		flacs.each do |flac|
			mp3task = flac.ext("mp3")
			mp3task = mp3task.sub( FLACDIR, MP3MIRROR )
			
			#transcode from flac->mp3
			#TODO: Don't transcode just because the flac tags have changed.
			file mp3task do
				puts("#{album}:#{flac} -> #{mp3task}")
				intermediate = mp3task.ext("xmp3")
				flaccommand = ["flac", "--decode", "--silent", "--stdout" ]
				lamecommand = ["lame"] + LAMEOPTS + [ "-" ]

				flaccommand = flaccommand.join(" ")
				flaccommand += " " + shell_escape( flac )
				lamecommand = lamecommand.join(" ")
				lamecommand += " " + shell_escape( intermediate )

				command = "#{flaccommand} | #{lamecommand}"
				puts( "mp3task: #{command }\n\n\n" )
				system( command ) or raise
				FileUtils.mv( intermediate, mp3task ) or raise "Can't rename #{intermediate} to #{mp3task}"
			end

			#copy the tags over.
			mp3tag = mp3task + "!tag"
			task mp3tag => mp3task
			task mp3tag do
				puts "Tagging #{mp3task}"
				#no flac write support yet :(
				flactags = FlacInfo.new( flac )
				Mp3Info.open( mp3task ) do |mp3info|
					#The swish thing about mp3info is that it keeps track of wheather it changed or not
					#so write away, it only does work if it has to.

					flactags.tags.each do |key, val|
						key = key.upcase
						#puts "tag: #{key}=#{val}"
						next unless tag_mapping.has_key?(key)
						target = tag_mapping[key]
						#Hack: Tracknum is an int in mp3 but str in flac
						if target == "tracknum" then val = val.to_i end	
						#puts "tag!: #{target}=#{val}"
						mp3info.tag[target] = val
					end
				end
			end

			#gather everything up...
			mp3do = mp3task + "!do"
			task mp3do => mp3task
			task mp3do => mp3tag
			task album => mp3do
		end
		
		#don't forget the pretty pictures...
		pictures = FileList["#{album}/*.jpg"] 
		pictures.each do |pic|
			mp3pic = pic.sub( FLACDIR, MP3MIRROR )
			file mp3pic do
				FileUtils.cp( pic, mp3pic )
			end
			task album => mp3pic
		end
	end #task albummp3prep
	
	albummp3 = album + "!mp3"
	task albummp3 => albummp3prep
	task albummp3 => album

	task :allalbums => albummp3
end

task :default => :allalbums


