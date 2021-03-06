
##  Very simple Twitter-IRC Bot which posts search results to IRC channel 
##     Goes offline when it doesnt find anything new after a while.
##     It saves the last posted tweed id, so it resume the search.
##
##   Sorry for that unproper code and dirty style.. it was more like a prove of concept .. which runs :D
##
###  Written by Matthias Strubel (c) 2013     matthias.strubel@aod-rpg.de
##       Licenced with GPL-3


use Net::Twitter;
use Scalar::Util 'blessed';

use Storable ;

use HTML::Entities ();


package Bot;
use base qw(Bot::BasicBot);
use warnings;
use strict;



use Data::Dumper;

my $last_search_id = {};
my $nt = Net::Twitter->new( traits => [qw/API::RESTv1_1/], 
	#Get these data from dev.twitter.com
      consumer_key        => 'x',
      consumer_secret     => 'x',
      access_token        => 'x',
      access_token_secret => 'x',
      ssl		  => 1,
);

my $MAX_TWEEDS_PER_SEARCH = 5 ;
my $TICK_COUNT = 30 ;   # tick every 30 seconds
my $MAX_EMPTY_CNT = 10 ;   # How much empty searches before disconnecting again
my $CACHE_FILE = "tweed_bot.cache";
my $EXCLUDE_RETWEETS = 1 ;


my $CHANNEL= "#piratebox" ;
my $CHANNEL_ARR = [ "$CHANNEL" ];

#don't connect to irc
my $DRY_RUN_ONLY = 0 ;

#----- IRC settings 
my $IRC_SERVER      = "irc.freenode.net" ;
my $IRC_SERVER_PORT =  "6667" ;
my $IRC_NICK        =  "PirateBox-Bot";
my $IRC_ALT_NICK    =  "PirateBox-Bot2";


my $Twitter_Search_String = "Piratebox";

my $bot ;
my $bot_run = 0;
my  $bot_wait_count = 0;
my $cnt_sent_tweeds = 0 ;
my $curr_empty =  $MAX_EMPTY_CNT ;

sub save_max_id ( $$ ) {
  my ( $string , $id ) = @_ ;


   if (  not $last_search_id->{$string} ) {
       $last_search_id->{$string} = $id;
   } else {
       if (  $last_search_id->{$string} < $id )  {
           $last_search_id->{$string} = $id;
       }
   }
}

sub perform_search ($$) {
   my $string       = shift;
   my $update_cache = shift;

   my $r = "";
   my $res_found = 0;

   my $api_string = $string ;
   if ( $EXCLUDE_RETWEETS ) { 
      print "Ignoring retweeds";
      $api_string .= "+exclude:retweets";
   }
   print "Starting twitter search...\n";
   if ( not $last_search_id->{$string} ) {
     print "Initial search with >$string< \n";
#     $r = $nt->search( { q=>"$string"  } );
      $r = $nt->search( { q=>"$api_string" , count=>"$MAX_TWEEDS_PER_SEARCH"  } );
   } else {
     #sinceID
     print "Follow up search with >$string< using ".$last_search_id->{$string} ."\n";
     $r = $nt->search( { q=>"$api_string"  , 
                         , count=>"$MAX_TWEEDS_PER_SEARCH" ,  
                         since_id=>$last_search_id->{$string}  } ); 
   }
 
   if ( $r ) {
#      print Dumper $r ;
    foreach my $result ( @{$r->{statuses}} ) {
       $result->{'cleaned_text'} = HTML::Entities::decode_entities ( $result->{'text'});
       $result->{'cleaned_text'} =~ s/\R/ /g;

       my $msg =  $result->{'user'}->{'name'} ." : ". $result->{'cleaned_text'}  ." - 
https://twitter.com/".$result->{'user'}->{'screen_name'}."/status/".$result->{'id'} ."\n" ;

       print $msg ;
       if (  $bot_run ) {
           bot_send_tweet ( $msg );
	   sleep (1);
       }
       if ( $update_cache ) {
           save_max_id( $string , $result->{'id'} ); 
       } else {
          print "Cache skipped..\n";
       }
       $res_found++;
    }
  } else {
    #Error?
    print Dumper $nt->get_error;
  } 
  return $res_found;
}


sub quit_message {

  my $msg = "Bye.. Served you  $cnt_sent_tweeds tweeds from twitter search >$Twitter_Search_String<" ;
  return $msg;
}

sub bot_start () {
   print "Starting bot against $IRC_SERVER:$IRC_SERVER_PORT \n";
   $bot = Bot->new(
    
      server => $IRC_SERVER ,
      port   => $IRC_SERVER_PORT ,
      channels =>  $CHANNEL_ARR ,
      nick => $IRC_NICK ,
      alt_nick => $IRC_ALT_NICK ,

    );

        
    $bot_run = 1;
    $bot->run();

}

sub bot_send_tweet  {
  my $message = shift;
  
  $bot->say ( "channel" => $CHANNEL , body => "$message" );
  $cnt_sent_tweeds++;
}


sub tick {
  my $self = shift;

  my $cnt = perform_search (  $Twitter_Search_String  , 1);

  if ( $cnt == 0 ) {
      if (   $curr_empty-- <= 0 ) {
            print "Shutdown bot because there where no new tweeds anymore\n";
            my $msg =   $bot->quit_message() ;
            $bot->shutdown( );
      }
  } else {
    $curr_empty = $MAX_EMPTY_CNT ;
  }

  return  $TICK_COUNT ;
}

#-----------------


#if file exists
if ( -e  $CACHE_FILE ) {
  print "Cache file $CACHE_FILE  exists, loading..";
  open ( my $fh , "< $CACHE_FILE " ) or die "can't open cache";
  eval {   $last_search_id = Storable::fd_retrieve ( $fh );  } ;
  close ( $fh );
  print "done \n";
} else {
  print "No cache file found..\n";
}


#Check if if have anything new
if ( perform_search("Piratebox" , 0 ) > 0 ) {

   if ( $DRY_RUN_ONLY ) {
      exit ;
   }
   eval { bot_start; } ;
}

print "Writing cache file $CACHE_FILE  .. ";
open ( my $output_fh, "> $CACHE_FILE ") or die "can't open cache for output" ;
Storable::store_fd ( $last_search_id , $output_fh ) || die "can't store cache \n";
close ( $output_fh );
print "done \n";
