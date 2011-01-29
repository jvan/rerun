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

# Setup directories and environmental variables
#export RERUN_DIR=`mktemp -d -t rerun.XXXXX`

export RERUN_DIR=/tmp/rerun

if [[ ! -e $RERUN_DIR ]]; then
   echo "Creating rerun directory"
   mkdir $RERUN_DIR
fi

rerun() {

   ################################################################################
   # Internal Functions
   #
   ################################################################################

   local ncat
   local get_hist_cmd
   local split_range
   local parse_hist_ids
   
   # Print contents of a file with line numbers
   ncat() {
      index=0
      while read line
      do
         printf "[%d] %s\n" $index "$line"
         index=$((index+1))
      done <$1
   }

   get_hist_cmd() {
      history | grep "^[ ]*$1" | sed "s/^[ ]*[0-9]*[ ]*//g"
   }

   split_range() {
      echo "$1" | sed "s/\([0-9]*\)-\([0-9]*\)/\1 \2/g"
   }

   HIST_IDS=()

   parse_hist_ids() {
      HIST_IDX=0
      for arg in $*
         do
            if [[ "$arg" =~ "-" ]]; then
               range=`split_range $arg`
               for i in `seq $range`
               do
                  HIST_IDS[$HIST_IDX]=$i
                  HIST_IDX=$((HIST_IDX+1))
               done
            else
               HIST_IDS[$HIST_IDX]=$arg
               HIST_IDX=$((HIST_IDX+1))
            fi
         done
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

   # Cleanup macros which have been removed via 'unset'
   for file in $RERUN_DIR/*
   do
      declare -f `basename $file` | grep "$RERUN_DIR" >& /dev/null
      if [[ $? -eq 1 ]]; then
         rm -f $macro
      fi
   done

   ACTION=$1
   shift

   case "$ACTION" in
     
      create)
         MACRO_NAME=$1
         # Bailout if the macro is already defined
         if [[ -e $RERUN_DIR/$MACRO_NAME ]];then
            echo "ERROR: macro file already exists."
            return 1
         fi

         echo " -- Creating macro [$MACRO_NAME]"
         
         # Get the history ids
         shift
         parse_hist_ids $*

         # Get commands from history and add them to the macro file
         for hist_id in ${HIST_IDS[@]}
         do
            cmd=`get_hist_cmd $hist_id`
            echo $cmd >> $RERUN_DIR/$MACRO_NAME
         done

         # Print the macro file
         ncat $RERUN_DIR/$MACRO_NAME
         
         # Make the macro file executable
         chmod +x $RERUN_DIR/$MACRO_NAME
         
         # Create a function with the macro name
         eval "$MACRO_NAME"'()' '{' 'eval' '"$(<'"$RERUN_DIR/$MACRO_NAME"')";' '}' 
         ;;
      list)
         # If no macro name is specified print out the names of all
         # existing macros.
         if [[ $# -eq 0 ]]; then
            echo " -- Macros:"
            for file in $RERUN_DIR/*
            do
               [[ -x $file ]] && echo "  `basename $file`"
            done
         # Otherwise, print out the contents of the macro file
         else
            MACRO_NAME=$1
            check_macro_file_exists $MACRO_NAME || return $?

            echo " -- Macro [$MACRO_NAME]"
            ncat $RERUN_DIR/$MACRO_NAME
         fi
         ;;
      append)
         # Add commands to the end of an existing macro
         MACRO_NAME=$1
         check_macro_file_exists $MACRO_NAME || return $? 
         
         echo " -- Appending macro [$MACRO_NAME]"

         # Get the history ids
         shift
         parse_hist_ids $*
         
         # Print the original macro file
         ncat $RERUN_DIR/$MACRO_NAME

         for hist_id in ${HIST_IDS[@]}
         do
            cmd=`get_hist_cmd $hist_id`
            echo $cmd >> $RERUN_DIR/$MACRO_NAME
         done

         # Print the modified macro file 
         echo "------------------------------>"
         ncat $RERUN_DIR/$MACRO_NAME
         ;;
      insert)
         # Insert commands into an existing macro
         MACRO_NAME=$1
         check_macro_file_exists $MACRO_NAME || return $? 

         echo " -- Inserting into macro [$MACRO_NAME]"
         
         # Get the index of the insertion point
         CMD_POS=$2
         
         # Get the history ids
         shift
         shift
         parse_hist_ids $*

         # Print the original macro file
         ncat $RERUN_DIR/$MACRO_NAME
         
         idx=0
         for hist_id in ${HIST_IDS[@]}
         do
            cmd=`get_hist_cmd $hist_id`
            pos=$(($CMD_POS+$idx))
            sed -i "$pos"a"$cmd" $RERUN_DIR/$MACRO_NAME
            idx=$((idx+1))
         done

         # Print the modified macro file 
         echo "------------------------------>"
         ncat $RERUN_DIR/$MACRO_NAME
         ;;
      remove)
         # Remove a command from an existing macro
         MACRO_NAME=$1
         check_macro_file_exists $MACRO_NAME || return $? 

         echo " -- Removing from macro [$MACRO_NAME]"
         
         # Get the index of item to be removed
         CMD_POS=$2
         
         # Print the original macro file
         ncat $RERUN_DIR/$MACRO_NAME

         sed -i $((CMD_POS+1))d $RERUN_DIR/$MACRO_NAME

         # Print the modified macro file 
         echo "------------------------------>"
         ncat $RERUN_DIR/$MACRO_NAME
         ;;
      delete)
         # Delete an existing macro
         MACRO_NAME=$1
         check_macro_file_exists $MACRO_NAME || return $? 

         # Remove the macro file and unset the function
         echo " -- Deleting macro [$MACRO_NAME]"
         rm -f $RERUN_DIR/$MACRO_NAME
         unset $MACRO_NAME
         ;;
      
      *) 
         echo "ERROR: unrecognized action."
         return 1
         ;;
   esac
}
