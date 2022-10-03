#!/bin/bash

# helm template (even with --dry-run) can interact with the cluster
# This won't protect us if a user has ~/.kube
# Also call helm template with a non existing --kubeconfig while we're at it
unset KUBECONFIG
target=$1
name=$(echo $1 | sed -e s@/@-@g -e s@charts-@@)

function doTest() {
    TEST_VARIANT=$1
    CHART_OPTS="$2"
    TESTDIR=tests
    TEST=${name}-${TEST_VARIANT}
    FILENAME=${TEST}.expected.yml
    OUTPUT=${TESTDIR}/.${FILENAME}
    REFERENCE=${TESTDIR}/${FILENAME}

    echo -e "\nTesting $name chart (${TEST_VARIANT}) with opts [$CHART_OPTS]" >&2
    helm template --kubeconfig /tmp/doesnotexistever $target --name-template $name ${CHART_OPTS} > ${OUTPUT}
    rc=$?
    if [ $rc -ne 0 ]; then
	echo "FAIL on helm template $target --name-template $name ${CHART_OPTS}"  >&2
	exit 1
    fi
    if [ ! -e ${REFERENCE} ]; then
	cp ${OUTPUT} ${REFERENCE}
	echo -e "\n\n#### Created test output\007\n#### Now add ${REFERENCE} to Git\n\n\007"  >&2
	exit 2
    fi
    diff -u ${REFERENCE} ${OUTPUT}
    rc=$?
    if [ $rc = 0 ]; then
	rm -f ${TESTDIR}/.${name}.*
	echo "PASS" >&2
    elif [ -z $GITHUB_ACTIONS ]; then
	read -p "Are these changes expected? [y/N]  " EXPECTED
	case $EXPECTED in
	    y*|Y*)
		echo "Updating ${REFERENCE}"
		cp ${OUTPUT} ${REFERENCE}
		rc=0
		;;
	    *) ;;
	esac
    fi
    if [ $rc != 0 ]; then
	echo "FAIL" >&2
	exit $rc
    fi
}

function doTestCompare() {
    TEST_VARIANT="differences"
    TESTDIR=tests
    TEST=${name}
    FILENAME=${TEST}.expected.yml
    OUTPUT=${TESTDIR}/.${FILENAME}
    REFERENCE=${TESTDIR}/${FILENAME}

    echo -e "\nTesting $name chart (${TEST_VARIANT})" >&2
    # Another method of finding variables missing from values.yaml, eg.
    # -    name: -datacenter
    # +    name: pattern-name-datacenter

    TEST=${name}
    FILENAME=${TEST}.expected.diff
    OUTPUT=${TESTDIR}/.${FILENAME}
    REFERENCE=${TESTDIR}/${FILENAME}

    # Drop the date from the diff output, it will not be stable
    diff -u ${TESTDIR}/${name}-naked.expected.yml ${TESTDIR}/${name}-normal.expected.yml | sed 's/\.yml.*20[0-9][0-9].*/.yml/g' > ${OUTPUT}

    if [ ! -e ${REFERENCE} ]; then	
	cp ${OUTPUT} ${REFERENCE}
	echo -e "\n\n#### Created test output\007\n#### Now add ${REFERENCE} to Git\n\n\007"  >&2
	exit 2
    fi

    diff -u ${REFERENCE} ${OUTPUT}
    rc=$?

    if [ $rc = 0 ]; then
	rm -f ${TESTDIR}/.${name}.*
	echo "PASS" >&2
    elif [ -z $GITHUB_ACTIONS ]; then
	read -p "Are these changes expected? [y/N]  " EXPECTED
	case $EXPECTED in
	    y*|Y*)
		echo "Updating ${REFERENCE}"
		cp ${OUTPUT} ${REFERENCE}
		rc=0
		;;
	    *) ;;
	esac
    fi
    if [ $rc != 0 ]; then
	echo "FAIL" >&2
	exit $rc
    fi
}

if [ $2 = "all" ]; then
    echo -e "\n#####################" >&2
    echo "### ${name}" >&2
    echo "#####################" >&2

    # Test that all values used by the chart are in values.yaml with the same defaults as the pattern
    doTest naked

    # Test the charts as the pattern would drive them
    doTest normal "$3"

    # Ensure the differences between the two results are also stable
    doTestCompare
else
    doTest $2 "$3"
fi

exit 0
