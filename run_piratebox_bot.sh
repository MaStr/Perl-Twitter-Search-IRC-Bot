#!/bin/bash 

# Can be used for cronjob

botfolder=/home/matze/piratebox_bot

semaphore=/tmp/piratebox_bot.semaphore

if [ -e $semaphore ] ; then
  exit 0
fi

cd $botfolder

touch $semaphore
perl tweets_search_bot.pl >> perl_bot.log
rm  $semaphore


