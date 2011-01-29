#
# NAME: rerun -- BASH history macro generator
#
# USAGE: rerun <ACTION> [OPTIONS]
#
#    rerun create MACRO
#    rerun list
#    rerun list MACRO
#    rerun append MACRO HIST_IDS
#    rerun insert MACRO POS HIST_IDS
#    rerun remove MACRO POS
#    rerun delete MACRO
#
# DESCRIPTION:
#    This program is used to create macros from commands from
#    the BASH history.
#

rerun() {

   ################################################################################
   # Internal Functions
   #
   ################################################################################

   local ncat
   local get_hist_cmd
   local parse_hist_ids
   
   # Print contents of a file with line numbers
   ncat() {
      local index=0
      local line
      while read line
      do
         printf "[%d] %s\n" $index "$line"
         index=$((index+1))
      done <$1
   }

   get_hist_cmd() {
      history | grep "^[ ]*$1" | sed "s/^[ ]*[0-9]*[ ]*//g"
   }

   parse_hist_ids() {
      local -a hist_ids=()
      local arg
      for arg in $*
      do
         if [[ "$arg" =~ "-" ]]; then
            hist_ids+=($(seq ${arg/-/ }))
         else
            hist_ids+=($arg)
         fi
      done
      echo ${hist_ids[*]}
   }

   check_macro_file_exists() {
      if [[ ! -e $RERUN_DIR/$1 ]]; then
         echo "ERROR: macro file does not exist."
         return 1
      fi
   }


   ################################################################################
   # Main Program
   #
   ################################################################################

   # Setup directories and global variables
   RERUN_DIR=${RERUN_DIR:=$(mktemp -d -t rerun.XXXXX)}
   mkdir -p "$RERUN_DIR"

   # Cleanup macros which have been removed via 'unset'
   for file in $RERUN_DIR/*
   do
      declare -f `basename $file` | grep "$RERUN_DIR" >& /dev/null
      if [[ $? -eq 1 ]]; then
         rm -f $file
      fi
   done

   local action=$1; shift

   case "$action" in
     
      create)
         local macro_name=$1; shift
         # Bailout if the macro is already defined
         if [[ -e $RERUN_DIR/$macro_name ]];then
            echo "ERROR: macro file already exists."
            return 1
         fi

         echo " -- Creating macro [$macro_name]"
         
         # Get commands from history and add them to the macro file
         local hist_id
         for hist_id in $(parse_hist_ids $*)
         do
            cmd=`get_hist_cmd $hist_id`
            echo $cmd >> $RERUN_DIR/$macro_name
         done

         # Print the macro file
         ncat $RERUN_DIR/$macro_name
         
         # Make the macro file executable
         chmod +x $RERUN_DIR/$macro_name
         
         # Create a function with the macro name
         eval "$macro_name"'()' '{' 'eval' '"$(<'"$RERUN_DIR/$macro_name"')";' '}' 
         ;;
      list)
         # If no macro name is specified print out the names of all
         # existing macros.
         if [[ $# -eq 0 ]]; then
            echo " -- Macros:"
            local file
            for file in $RERUN_DIR/*
            do
               [[ -x $file ]] && echo "  `basename $file`"
            done
         # Otherwise, print out the contents of the macro file
         else
            local macro_name=$1
            check_macro_file_exists $macro_name || return $?

            echo " -- Macro [$macro_name]"
            ncat $RERUN_DIR/$macro_name
         fi
         ;;
      append)
         # Add commands to the end of an existing macro
         local macro_name=$1; shift
         check_macro_file_exists $macro_name || return $? 
         
         echo " -- Appending macro [$macro_name]"

         # Print the original macro file
         ncat $RERUN_DIR/$macro_name

         local hist_id
         for hist_id in $(parse_hist_ids $*)
         do
            local cmd=`get_hist_cmd $hist_id`
            echo $cmd >> $RERUN_DIR/$macro_name
         done

         # Print the modified macro file 
         echo "------------------------------>"
         ncat $RERUN_DIR/$macro_name
         ;;
      insert)
         # Insert commands into an existing macro
         local macro_name=$1; shift
         check_macro_file_exists $macro_name || return $? 

         echo " -- Inserting into macro [$macro_name]"
         
         # Get the index of the insertion point
         local cmd_pos=$1; shift

         # Print the original macro file
         ncat $RERUN_DIR/$macro_name
         
         local idx=0
         local hist_id
         for hist_id in $(parse_hist_ids $*)
         do
            local cmd=`get_hist_cmd $hist_id`
            local pos=$(($cmd_pos+$idx))
            sed -i "$pos"a"$cmd" $RERUN_DIR/$macro_name
            idx=$((idx+1))
         done

         # Print the modified macro file 
         echo "------------------------------>"
         ncat $RERUN_DIR/$macro_name
         ;;
      remove)
         # Remove a command from an existing macro
         local macro_name=$1
         check_macro_file_exists $macro_name || return $? 

         echo " -- Removing from macro [$macro_name]"
         
         # Get the index of item to be removed
         local cmd_pos=$2
         
         # Print the original macro file
         ncat $RERUN_DIR/$macro_name

         sed -i $((cmd_pos+1))d $RERUN_DIR/$macro_name

         # Print the modified macro file 
         echo "------------------------------>"
         ncat $RERUN_DIR/$macro_name
         ;;
      delete)
         # Delete an existing macro
         local macro_name=$1
         check_macro_file_exists $macro_name || return $? 

         # Remove the macro file and unset the function
         echo " -- Deleting macro [$macro_name]"
         rm -f $RERUN_DIR/$macro_name
         unset $macro_name
         ;;
      
      *) 
         echo "ERROR: unrecognized action."
         return 1
         ;;
   esac
}

