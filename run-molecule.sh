#!/usr/bin/bash

if [[ ! -r ~/.venv/molecule/bin/activate ]]
then
  echo need to configure venv first, check documentation!
  exit 1
else
  source ~/.venv/molecule/bin/activate
fi

if ! hash molecule >/dev/null 2>&1
then
  echo need to install molecule into your venv, check documentation!
  exit 1
fi

TESTABLE_ON_ARM_ONLY="integration doesnotexistyet"

ALL_SCENARIOS=$( cd molecule; find . -mindepth 1 -maxdepth 1 -type d | sed -e "s|^\./||" )

for scenario in $ALL_SCENARIOS
do
  for denied in $TESTABLE_ON_ARM_ONLY
  do
    if [[ "$scenario" == "$denied" ]]
    then
      SKIPPED="$SKIPPED $scenario"
      continue 2
    fi
  done
  molecule --base-config molecule/config.yml test -s $scenario
  EXECUTED="$EXECUTED $scenario"
done
echo ""
echo "Executed scenarios:${EXECUTED}"
echo "Skipped  scenarios:${SKIPPED}"
