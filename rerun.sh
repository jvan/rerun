#
# NAME: rerun -- BASH history macro generator
#
# USAGE: rerun <action> [args]
#    rerun create <macro name> [history ids] [...]
#    rerun list
#    rerun list <macro name>
#    rerun append <macro name> <history ids> [...]
#    rerun insert <macro name> <position> <history ids> [...]
#    rerun remove <macro name> <position>
#    rerun edit <macro name>
#    rerun delete <macro name>
#
# DESCRIPTION:
#    This program is used to create macros from commands from
#    the BASH history.
 #

################################################################################
# Internal Functions
#
################################################################################

# Print contents of a file with line numbers
__rerun_ncat() {
   local index=0
   while read; do
      printf "%3d  %s\n" $((index++)) "$REPLY"
   done <$1
}

__rerun_diff_ncat() {
   local index=0
   echo "$1" | diff -u99 - "$2" | tail -n+4 | while read; do
      echo -n "${REPLY:0:1}"
      if [[ ${REPLY:0:1} == '-' ]]; then
         echo -n "    "
      else
         printf '%2d  ' $index
         ((++index))
      fi
      echo "${REPLY:1}"
   done
}

__rerun_parse_hist_ids() {
   local -a hist_ids=()
   local arg
   for arg in $*
   do
      if [[ "$arg" =~ ^[0-9]+-[0-9]+$ ]]; then
         eval hist_ids+=({${arg/-/..}})
      elif [[ "$arg" =~ ^(-?[0-9]+):([0-9]+)$ ]]; then
         local start=${BASH_REMATCH[1]}
         local count=${BASH_REMATCH[2]}
         eval hist_ids+=({$start..$((start+$count-1))})
      elif [[ "$arg" =~ ^(-?[0-9]+)([.-]+)$ ]]; then
         local id=${BASH_REMATCH[1]}
         local spec=${BASH_REMATCH[2]}
         hist_ids+=($id)
         local c
         for c in $(fold -w1 <<<$spec); do
            ((++id))
            [[ $c == '.' ]] && hist_ids+=($id)
         done
      else
         hist_ids+=($arg)
      fi
   done
   echo ${hist_ids[*]}
}

__rerun_get_macro_path() {
   echo "$RERUN_DIR/$1"
   if [[ ! -x "$RERUN_DIR/$1" ]]; then
      echo "ERROR: macro $1 does not exist." >&2
      return 1
   fi
}

__rerun_exec() {
   if (($#!=0)); then
      local action=$1; shift
      rerun "$action" "${FUNCNAME[1]}" "$@"
   else
      "$RERUN_DIR"/"${FUNCNAME[1]}"
   fi
}

__rerun_do_create() {
   local macro_name=$1; shift
   # Bailout if the macro is already defined
   local macro; macro=$(__rerun_get_macro_path "$macro_name" 2>/dev/null)
   if (($?==0)); then
      echo "ERROR: macro file already exists."
      return 1
   fi
   touch "$macro"

   echo " -- Creating macro [$macro_name]"
   
   # Get commands from history and add them to the macro file
   local hist_id
   for hist_id in $(__rerun_parse_hist_ids $*)
   do
      echo $(history -p '!'$hist_id) >> "$macro"
   done

   # Print the macro file
   __rerun_ncat "$macro"
   
   # Make the macro file executable
   chmod +x "$macro"
   
   # Create a function with the macro name
   eval "$macro_name"'()' '{' '__rerun_exec' '"$@";' '}' 
}

__rerun_do_list() {
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
      local macro; macro=$(__rerun_get_macro_path "$macro_name") || return $?

      echo " -- Macro [$macro_name]"
      __rerun_ncat "$macro"
   fi
}

__rerun_do_append() {
   # Add commands to the end of an existing macro
   local macro_name=$1; shift
   local macro; macro=$(__rerun_get_macro_path "$macro_name") || return $?
   
   echo " -- Appending macro [$macro_name]"

   local orig=$(<"$macro")

   local hist_id
   for hist_id in $(__rerun_parse_hist_ids $*)
   do
      echo $(history -p '!'$hist_id) >> "$macro"
   done

   __rerun_diff_ncat "$orig" "$macro"
}

__rerun_do_insert() {
   # Insert commands into an existing macro
   local macro_name=$1; shift
   local macro; macro=$(__rerun_get_macro_path "$macro_name") || return $?

   echo " -- Inserting into macro [$macro_name]"
   
   # Get the index of the insertion point
   local cmd_pos=$(($1+1)); shift

   local orig=$(<"$macro")
   
   local idx=0
   local hist_id
   for hist_id in $(__rerun_parse_hist_ids $*)
   do
      local cmd=$(history -p '!'$hist_id)
      local pos=$(($cmd_pos+$idx))
      sed -i "$pos"i"$cmd" "$macro"
      ((++idx))
   done

   __rerun_diff_ncat "$orig" "$macro"
}

__rerun_do_remove() {
   # Remove a command from an existing macro
   local macro_name=$1
   local macro; macro=$(__rerun_get_macro_path "$macro_name") || return $?

   echo " -- Removing from macro [$macro_name]"
   
   # Get the index of item to be removed
   local cmd_pos=$2
   
   local orig=$(<"$macro")

   sed -i $((cmd_pos+1))d "$macro"

   __rerun_diff_ncat "$orig" "$macro"
}

__rerun_do_edit() {
   local macro_name=$1
   local macro; macro=$(__rerun_get_macro_path "$macro_name") || return $?
   local orig=$(<"$macro")
   ${VISUAL:-${EDITOR:-vi}} "$macro"
   __rerun_diff_ncat "$orig" "$macro"
}

__rerun_do_delete() {
   # Delete an existing macro
   local macro_name=$1
   local macro; macro=$(__rerun_get_macro_path "$macro_name") || return $?

   # Remove the macro file and unset the function
   echo " -- Deleting macro [$macro_name]"
   rm -f "$macro"
   unset "$macro_name"
}

__rerun_return_help() {
   eval "$(sed '1,3d;/^[^#]/Q;s/^# \?\(.*\)$/echo "\1";/' $__rerun_source_path)"
   return 2
}

rerun() {

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
      declare -f `basename $file` | grep "__rerun_exec" >& /dev/null
      if [[ $? -eq 1 ]]; then
         rm -f $file
      fi
   done

   local action=$1; shift

   case "$action" in
     
      c|cr|cre|crea|creat|create)
         __rerun_do_create "$@" || return $?
         ;;

      l|li|lis|list)
         __rerun_do_list "$@" || return $?
         ;;
         
      a|ap|app|appe|appen|append)
         __rerun_do_append "$@" || return $?
         ;;

      i|in|ins|inse|inser|insert)
         __rerun_do_insert "$@" || return $?
         ;;
         
      r|re|rem|remo|remov|remove)
         __rerun_do_remove "$@" || return $?
         ;;
         
      e|ed|edi|edit)
         __rerun_do_edit "$@" || return $?
         ;;

      d|de|del|dele|delet|delete)
         __rerun_do_delete "$@" || return $?
         ;;
         
      '')
         __rerun_return_help
         return $?
         ;;

      *) 
         echo "ERROR: unrecognized action \"$action\"."
         __rerun_return_help
         return $?
         ;;
   esac
}

# Get path to this source file
__rerun_source_path=$(f(){ readlink -f "$BASH_SOURCE";};f)
