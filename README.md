# gtest_parallel_for_dev

# Example output

safe_run.ps1
```
.
├── change.patch              # change logs, you can git apply to observe the change not committed
├── fail                      # failed tests
├── fail_gtest_filter.ps1     # the failed list, uncomment ``# Invoke-Expression ". $fail_filter_path" # get test list from previous tests` just to run failed and timeout list
├── git.log                   # your project git log to memory the commit
├── running_0.log             # the running task 1
├── running_1.log
├── running_2.log
├── running_3.log
├── running_4.log
├── success                   # success log
└── test_list.txt             # all tests names

```

# features
## local getsts

some projects use a remote source of cmake, you can use your local version,
just set `$gtest_path`

## batch test

For large scale tests, you can adjust:
```
$timeout_minutes = @(5, 5, 2, 1)
$wait_time=1 #wait 1 second
$job_nums = @(8, 32, 8, 4)
$batch_nums = @(64, 1, 1, 1)
```
To combine small tests into batch (random) to parallel run.
The batch is a single test program to run the test.
## retry

Some Tests have random behaviors, you can set `$retry_times`

## git clone

To archive your code, you can set `$need_clone=$true`,
which put the source in `$build_path`,
And if you want to change sources during your test,
that will help a lot.

## git logs

This script records git logs and uncommitted code in the `$log_path`

## Timeout and Interrupt

the timeout and interrupt can handled if you set reasonable `$timeout_minutes = @(5, 5, 2, 1)`

Enjoy It
