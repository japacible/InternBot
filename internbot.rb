require 'socket'
require 'uri'
require 'InternDB'
require 'IRCHole'
require 'rubygems'
require 'sqlite3'

class InternBot
    @@irc = nil
    @@admin_prefix = "sudo "

    @@server = "irc.amazon.com"
    @@port = "6667"
    @@nick = "internbot" # TODO make "#{@@nick}[stfu]" when on STFU mode
    @@channel = "#intern-chatter"

    @@commands = {
        "face" => {
            :auth       => :normal, # does this require an op to give the command?
            :exact_args => 1,     # an exact arg is an argument without a space
            :excess     => false, # whether other "excess" args are wanted
            :func  => lambda { |nick, arg|
                @@irc.putraw "WHOIS #{arg}"
                whois = @@irc.getraw
                whois = whois.split(" ")[4]
                if arg == @@nick
                    return "Do I look like a bitch to you?"
                end
                if whois != ":No"
                    return "#{arg}'s face: https://internal.amazon.com/phone/phone-image.cgi?uid=#{whois}"
                else
                    return "This IRC user is faceless. Find nearest shelter."
                end
            },
        },

        "whois" => {
            :auth       => :normal,
            :exact_args => 1,
            :excess     => false,
            :func  => lambda { |nick, arg|
                @@irc.putraw "WHOIS #{arg}"
                whois = @@irc.getraw
                whois = whois.split(" ")[4]
                if arg == @@nick
                    return "Do I look like a bitch to you?"
                end
                if whois != ":No"
                    return "#{arg}'s lookup: https://contactstool.amazon.com/ac/can/people/find/#{whois}"
                else
                    return "This IRC user is faceless. Find nearest shelter."
                end
            },
        },

        "bro me"  => {
            :auth       => :normal,
            :exact_args => 0,
            :excess     => false,
            :func  => lambda { |nick|
                return "Sure thing, " + InternDB.random_bro + "."
            },
        },
        
        "nyan me"  => {
            :auth       => :normal,
            :exact_args => 1,
            :excess     => false,
            :func  => lambda { |nick, nyans|
                nyans = nyans.to_i
                if nyans <= 0
                  return
                end
                nyans-=1
                nyan_out="nyan"
                nyans.times do 
                  nyan_out << " nyan"
                  if nyan_out.length > 426
                    break
                  end
                end
                return nyan_out
            },
        },
        
        "sudo nyan me"  => {
            :auth       => :normal,
            :exact_args => 1,
            :excess     => false,
            :func  => lambda { |nick, nyans|
              if @@irc.op? nick
                nyans = nyans.to_i
                if nyans <= 0
                  return
                end
                nyans-=1
                nyan_out="nyan"
                nyans.times do 
                  if nyan_out.length > 421
                    @@irc.speak nyan_out
                    nyan_out = "nyan"
                  else
                    nyan_out << " nyan"
                  end
                end
                @@irc.speak nyan_out
                return
              end
            },
        },
=begin        
        "come at me bro" => {
            :auth       => :normal,
            :exact_args => 0,
            :excess     => false,
            :func  => lambda { |nick|
              if @@irc.op? nick
                @@irc.putraw "KICK #{@@channel} #{@@irc.list[rand @@irc.list.size]}"
              elsif
                @@irc.putraw "KICK #{@@channel} #{nick}"
              end
            },
        },
=end        
        "nyan spam" => {
            :auth       => :op,
            :exact_args => 1,
            :excess     => false,
            :func => lambda { |nick, nyans|
              nyans = nyans.to_i
              nyans.times do 
                @@irc.speak "nyan"
              end
              return
          },
        },

        "add bro" => {
            :auth       => :normal,
            :exact_args => 0,
            :excess     => true,
            :func  => lambda { |nick, bro|
                InternDB.add_bro(bro)
                return "Bro added."
            },
        },

        "ice bro" => {
            :auth       => :op,
            :exact_args => 0,
            :excess     => true,
            :func  => lambda { |nick, bro|
                InternDB.remove_bro(bro)
                return "Iced. Smooth move, brah."
            },
        },

        "op" => {
            :auth       => :op,
            :exact_args => 1,
            :excess     => false,
            :func  => lambda { |nick, arg|
                @@irc.putraw "WHOIS #{arg}"
                whois = @@irc.getraw
                whois = whois.split(" ")[4]
                InternDB.add_op(arg, whois)
                @@irc.op arg
                return "#{arg} welcomed into the magical kingdom."
            },
        },

        "deop" => {
            :auth       => :op,
            :exact_args => 1,
            :excess     => false,
            :func  => lambda { |nick, arg|
                InternDB.remove_op arg
                @@irc.deop arg
                return "#{arg} shunned from the magical forest of ents and things."
            },
        },

        # TODO change punish to voice/devoice at max users per command
        #"punish" => {
        #    :auth       => :op,
        #    :exact_args => 1,
        #    :excess     => false,
        #    :func  => lambda { |nick, user|
        #        @@irc.punish user
        #        return "#{user} being whipped sexily."
        #    },
        #},
        #"neutralize" => {
        #    :auth       => :op,
        #    :exact_args => 0,
        #    :excess     => false,
        #    :func  => lambda { |nick|
        #        @@irc.neutralize
        #        return "All is well again."
        #    },
        #},
        "make me a" => {
            :auth       => :op,
            :exact_args => 0,
            :excess     => true,
            :func  => lambda { |nick, arg|
                arg = arg.join(" ") if arg.kind_of? Array
                if arg.empty?
                    return
                end
                return "Make your own damn #{arg}"
            },
        },

        "say" => {
            :auth       => :op,
            :exact_args => 0,
            :excess     => true,
            :func => lambda { |nick, arg|
                arg = arg.join(" ") if arg.kind_of? Array
                if arg.empty?
                    return
                end
                @@irc.speak arg
                return nil
            }
        },

        "#{@@nick} stfu" => {
            :auth       => :op,
            :exact_args => 0,
            :excess     => false,
            :func  => lambda { |nick|
                # workaround because you can't speak after stfu
                @@irc.speak "going stealth."
                @@irc.stfu
            },
        },

        "#{@@nick} wtfu" => {
            :auth       => :op,
            :exact_args => 0,
            :excess     => false,
            :func  => lambda { |nick|
                @@irc.wtfu
                return "so now you need me."
            },
        },

        "#{@@nick} gtfo" => {
            :auth       => :op,
            :exact_args => 0,
            :excess     => false,
            :func  => lambda { |nick|
                @@irc.speak "whateva."
                @@irc.putraw "QUIT"
                exit
            },
        },
    }

    class << self

        def start(db)
            InternDB.connect(db)
            @@irc = IRCHole.new(@@server, @@port, @@nick, @@channel, method(:command_handler))
            @@irc.start
        end

        def command_handler(priv, nick, amzn_user, msg)
            # SPECIAL CASE: commands listings.
            if msg.start_with? "#{@@nick} commands"
                cmdlist = []
                @@commands.each do |command, cmd_info|
                    if cmd_info[:auth] == :op and InternDB.is_op?(nick, amzn_user)
                        cmdlist << "sudo " + command
                    elsif cmd_info[:auth] != :op
                        cmdlist << command
                    end
                end
                @@irc.speak cmdlist.join(' ')
            end
            # check if the message is a given command
            @@commands.each do |command, cmd_info|
                # apply admin prefix
                if cmd_info[:auth] == :op and not InternDB.is_op?(nick, amzn_user)
                    next
                elsif cmd_info[:auth] == :op
                    command = @@admin_prefix + command
                end

                if (cmd_info[:exact_args] > 0 and msg.start_with?(command+" ")) or (cmd_info[:exact_args] == 0 and msg.start_with?(command))
                    msg = msg[(command.length+1)..-1].strip # cut off command from message
                    @@irc.debug "command: "+command

                    # put args in array, and the excess as a string
                    if cmd_info[:exact_args] > 0
                        args = msg.split(" ")[0..(cmd_info[:exact_args]-1)]
                    else
                        args = []
                    end
                    if cmd_info[:excess]
                        args << msg.split(" ")[cmd_info[:exact_args]..-1].join(" ")
                    end
                    if args.length < cmd_info[:exact_args]
                        break
                    end
                    response = cmd_info[:func].call(nick, *args)
                    if priv
                        @@irc.privmsg(response, nick) unless not response
                    else
                        @@irc.speak(response) unless not response
                    end
                    break # out of the command loop if we found on successfully
                end
            end
        end
    end
end
