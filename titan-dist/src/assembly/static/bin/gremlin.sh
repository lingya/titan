#!/bin/bash

set -e
set -u

# Environment variables that affect this script:
#
# TITAN_JAVA_OPTS
#
#   When set to a nonempty value, this variable is interpreted as a
#   set of additional VM options.  These options are appended after
#   the default JVM options that this script normally sets.  This is
#   the preferred way to specify additional VM options.
#
# JAVA_OPTIONS
#
#   When set to a nonempty value, this variable is interpreted as a
#   completel list of VM options.  This script will invoke the VM with
#   exactly the options specified in the variable.  This is rarely
#   preferable to TITAN_JAVA_OPTS, but it's available in unusual cases
#   where the default VM options need to be omitted.  Note that the
#   classpath is passed to the VM by building a CLASSPATH environment
#   variable in this script and exporting it before invoking the VM,
#   not by a command-line option.  See the entry on CLASSPATH for more
#   information.
#
# CLASSPATH
#
#   When set to a nonempty value, this is prepended to the classpath
#   entries automatically generated by this script.
#
# SCRIPT_DEBUG
#
#   When set to a nonempty value, this makes the script noisier about
#   what it's doing.  The effect of this variable is limited to the
#   script.  It does not affect the Log4j/Slf4j log level in the JVM
#   (use the -l <LOGLEVEL> option for that).
#
# JAVA_HOME
#
#   When set to a nonempty value, this script will use the JVM binary
#   at the path $JAVA_HOME/bin/java.
#
# HADOOP_PREFIX, HADOOP_CONF_DIR, HADOOP_CONF, HADOOP_HOME
#
#   When set to a nonempty value, the script attempts to add to the
#   CLASSPATH the etc/hadoop or conf subdirectory of the Hadoop
#   install to the variable points.

# Returns the absolute path of this script regardless of symlinks
abs_path() {
    # From: http://stackoverflow.com/a/246128
    #   - To resolve finding the directory after symlinks
    SOURCE="${BASH_SOURCE[0]}"
    while [ -h "$SOURCE" ]; do
        DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
        SOURCE="$(readlink "$SOURCE")"
        [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
    done
    echo "$( cd -P "$( dirname "$SOURCE" )" && pwd )"
}

CP=`abs_path`/../conf
CP=$CP:$(find -L `abs_path`/../lib/ -name '*.jar' | tr '\n' ':')
CP=$CP:$(find -L `abs_path`/../ext/ -name '*.jar' | tr '\n' ':')

# Check some Hadoop-related environment variables
if [ -n "${HADOOP_PREFIX:-}" ]; then
    # Check Hadoop 2 first
    if [ -d "$HADOOP_PREFIX"/etc/hadoop ]; then
        CP="$CP:$HADOOP_PREFIX"/etc/hadoop
    elif [ -d "$HADOOP_PREFIX"/conf ]; then
        # Then try Hadoop 1
        CP="$CP:$HADOOP_PREFIX"/conf
    fi
elif [ -n "${HADOOP_CONF_DIR:-}" ]; then
    CP="$CP:$HADOOP_CONF_DIR"
elif [ -n "${HADOOP_CONF:-}" ]; then
    CP="$CP:$HADOOP_CONF"
elif [ -n "${HADOOP_HOME:-}" ]; then
    # Check Hadoop 2 first
    if [ -d "$HADOOP_HOME"/etc/hadoop ]; then
        CP="$CP:$HADOOP_HOME"/etc/hadoop
    elif [ -d "$HADOOP_HOME"/conf ]; then
        # Then try Hadoop 1
        CP="$CP:$HADOOP_HOME"/conf
    fi
fi

# Convert from *NIX to Windows path convention if needed
case `uname` in
    CYGWIN*) CP=`cygpath -p -w "$CP"`
esac

export CLASSPATH="${CLASSPATH:-}:$CP"

# Find Java
if [ -z "${JAVA_HOME:-}" ]; then
    JAVA="java -server"
else
    JAVA="$JAVA_HOME/bin/java -server"
fi

# Set default message threshold for Log4j Gremlin's console appender
if [ -z "${GREMLIN_LOG_LEVEL:-}" -o "${GREMLIN_MR_LOG_LEVEL:-}" ]; then
    GREMLIN_LOG_LEVEL=WARN
    GREMLIN_MR_LOG_LEVEL=INFO
fi

# Script debugging is disabled by default, but can be enabled with -l
# TRACE or -l DEBUG or enabled by exporting
# SCRIPT_DEBUG=nonemptystring to gremlin.sh's environment
if [ -z "${SCRIPT_DEBUG:-}" ]; then
    SCRIPT_DEBUG=
fi

# Process options
MAIN_CLASS=com.thinkaurelius.titan.hadoop.tinkerpop.gremlin.Console

while getopts "eilv" opt; do
    case "$opt" in
    e) MAIN_CLASS=com.thinkaurelius.titan.hadoop.tinkerpop.gremlin.ScriptExecutor
       # For compatibility with behavior pre-Titan-0.5.0, stop
       # processing gremlin.sh arguments as soon as the -e switch is
       # seen; everything following -e becomes arguments to the
       # ScriptExecutor main class
       shift $(( $OPTIND - 1 ))
       break;;
    i) MAIN_CLASS=com.thinkaurelius.titan.hadoop.tinkerpop.gremlin.InlineScriptExecutor
       # This class was brought in with Faunus/titan-hadoop. Like -e,
       # everything after this option is treated as an argument to the
       # main class.
       shift $(( $OPTIND - 1 ))
       break;;
    l) eval GREMLIN_LOG_LEVEL=\$$OPTIND
       GREMLIN_MR_LOG_LEVEL="$GREMLIN_LOG_LEVEL"
       OPTIND="$(( $OPTIND + 1 ))"
       if [ "$GREMLIN_LOG_LEVEL" = "TRACE" -o \
            "$GREMLIN_LOG_LEVEL" = "DEBUG" ]; then
	   SCRIPT_DEBUG=y
       fi
       ;;
    v) MAIN_CLASS=com.tinkerpop.gremlin.Version
    esac
done

if [ -z "${JAVA_OPTIONS:-}" ]; then
    JAVA_OPTIONS="-Dlog4j.configuration=log4j-gremlin.properties"
    JAVA_OPTIONS="$JAVA_OPTIONS -Dgremlin.log4j.level=$GREMLIN_LOG_LEVEL"
    JAVA_OPTIONS="$JAVA_OPTIONS -Dgremlin.mr.log4j.level=$GREMLIN_MR_LOG_LEVEL"
fi

if [ -n "${TITAN_JAVA_OPTS:-}" ]; then
    JAVA_OPTIONS="$JAVA_OPTIONS $TITAN_JAVA_OPTS"
fi

if [ -n "$SCRIPT_DEBUG" ]; then
    echo "CLASSPATH: $CLASSPATH"
    set -x
fi

# Start the JVM
$JAVA $JAVA_OPTIONS $MAIN_CLASS "$@"
