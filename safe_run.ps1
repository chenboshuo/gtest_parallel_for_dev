# Set-ExecutionPolicy Unrestricted
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
$source_path="Z:\"
$test_name = "cur_release"
$repeat_time=1
$test_title = $test_name
$log_path="Y:\logs\$test_name"
$fail_filter_path = "$log_path/fail_gtest_filter.ps1"
$run_cases="SurfSurfInterTest/*"
$test_list = @()
# Invoke-Expression ". $fail_filter_path" # get test list from previous tests
# $environment="Debug"
$environment="Release"
$build_path="C:\Users\User\Downloads\$test_name"
$target_exe="$build_path/build/$environment/tests_acis.exe"
$test_time=Get-Date -Format "yyyy-MM-dd HH.mm.ss";
$need_clone=$false
$need_build=$true
$timeout = 2*60  # set timeout seconds 
$wait_time=1 #wait 1 second
$job_num = 8


# check target log file
if ((Test-Path $log_path)) {
  $given_test_list = Test-Path $fail_filter_path
  $backup = "$log_path"+"_backup_$test_time"
  mv $log_path $backup 

  # keep fail list
  if($given_test_list){
    $fail_list_new_path = Split-Path $fail_filter_path -Parent
    mkdir -p $fail_list_new_path > $null
    cp "$backup/fail_gtest_filter.ps1"  $fail_list_new_path
  }
}
if (-not (Test-Path $log_path)) {
  mkdir -p $log_path > $null
}

# git clone
if ($need_clone){
    if($need_build){
      if (Test-Path "$build_path/src") {
          mv "$build_path/src" "$build_path/src_backup_$test_time"
      }
      git clone $source_path "$build_path/src"
    }
    $source_path="$build_path/src"
}

# wait
$host.UI.RawUI.WindowTitle = "$test_title[waiting]"
Start-Sleep -Seconds $wait_time

if($need_build){
  # build
  $host.UI.RawUI.WindowTitle = "$test_title[building]"
  # cmake
  if(-not(Test-Path "$build_path/build/GME.sln")){
      cmake -G "Visual Studio 17 2022"  -S "$source_path" -B "$build_path/build"
  }

  # build
  if (Test-Path $target_exe) {
      rm $target_exe
  }
  MSBuild $build_path/build/GME.sln  -target:gme_acis\tests_acis -property:Configuration=$environment;
}
if(-not (Test-Path -Path $target_exe)){
  $host.UI.RawUI.WindowTitle = "$test_title[error]"
  exit 1
}

# get list if no list is given
if($test_list.Count -eq 0){
  $get_list_command = "$target_exe" + 
    " --gtest_filter=$run_cases --gtest_list_tests > $log_path/test_list.txt"
  Invoke-Expression $get_list_command
  Get-Content -Path "$log_path/test_list.txt"| ForEach-Object {
    if ($_ -notmatch '^\s') {
      $cur_suite_name = $_
    }else{
      $case_name = $_ -replace '^\s+', ''
      $case_name = $case_name -replace '  #.*$', ''
      $test_list += "$cur_suite_name$case_name"
    }
  }
}

# run
$host.UI.RawUI.WindowTitle = "$test_title[$job_num jobs run]"

# 创建进度条
$progress = @{
    Activity = "test_all"
    CurrentOperation = "start"
    Status = "running"
    PercentComplete = 0
}

Write-Progress @progress
$test_id=0

$fail_test_list = New-Object System.Collections.ArrayList
$start_time=Get-Date
$fail_count = 0
$success_count = 0

$dumb_test_num
while ($test_list.Count % $job_num -ne 0){
  $test_list += "dumb_test_$dumb_test_num"
  $dumb_test_num += 1
}

# foreach ($case_name in $test_list){
for ($i = 0; $i -lt $test_list.Count; $i += $job_num) {
  $now=Get-Date

  $test_a_case = {
    param($case_name, $job_id)
    $test_time=Get-Date -Format "yyyy-MM-dd_HH.mm.ss";
    $PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
    $target_command="$using:build_path/build/$using:environment/tests_acis.exe" +
      " --gtest_repeat=$using:repeat_time"+
      " --gtest_filter=$case_name" + ";$" + "success=$" + "?"

    $command = {
      Invoke-Expression $target_command >> $using:log_path/running_$job_id.log;
    }
    $measurements = Measure-Command $command
    $executionTime = $measurements.TotalMilliseconds

    $memoryUsageBytes = (Get-Process -Id $pid).WorkingSet64
    $memoryUsageMB = $memoryUsageBytes / 1MB


    # info
    echo "Test start from $test_time To $(Get-Date -Format "yyyy-MM-dd_HH.mm.ss")" >> $using:log_path/running_$job_id.log 
    echo "time cost: $executionTime ms" >> $using:log_path/running_$job_id.log 
    echo "memory used: $memoryUsageMB MB" >>  $using:log_path/running_$job_id.log 
    
   
    $end_time=Get-Date
    if($success){ # success
      $new_log_loc = $using:log_path + "/success/" + $case_name + "_" + $test_time + ".log"
    }else{
      $new_log_loc = $using:log_path + "/fail/" + $case_name + "_" + $test_time + ".log"
    }
    $directory = Split-Path $new_log_loc -Parent
    New-Item -ItemType Directory -Path $directory -Force > $null
    mv $using:log_path/running_$job_id.log $new_log_loc -Force
    return $success
  } # end test a case

  $jobs = @()
  for($j=0; $j -lt $job_num; $j += 1){
    $job = Start-Job -ScriptBlock $test_a_case -ArgumentList $test_list[$i+$j], $j
    $jobs += $job
  }
  Wait-Job -Job $jobs -Timeout $timeout > $null

  # update progress
  $total_cost_time=($now-$start_time).ToString("dd' days 'hh':'mm':'ss")
  $progress.CurrentOperation = $test_list[$i .. ($i+$job_num-1)] -join ", " 
  
  $percent=($test_id / $test_list.Count) * 100
  $progress.PercentComplete = $percent 
  $progress.Status = "fail: $fail_count, success: $success_count [$total_cost_time] | $percent %"
  Write-Progress @progress
  $test_id += $job_num

  # 等待作业完成或超时
  # foreach($job in $jobs){
  for($job_id=0; $job_id -lt $job_num; $job_id +=1){
    $job = $jobs[$job_id]
    if ($job.State -eq 'Running') {
      # 如果超时，终止作业
      Stop-Job -Job $job
      $case_name = $test_list[$i+$job_id]
      echo "$case_name time exceed $timeout seconds."
      $case_string = $fail_test_list -join "`",`""
      echo "`$test_list=@(`"$case_string`")" > $log_path/fail_gtest_filter.ps1
      $fail_time=Get-Date -Format "yyyy-MM-dd_HH.mm.ss";
      $new_log_loc = $log_path + "/timeout/" + $test_list[$i+$job_id] + "_" + $fail_time + ".log"
      $directory = Split-Path $new_log_loc -Parent
      New-Item -ItemType Directory -Path $directory -Force > $null
      mv $log_path/running_$job_id.log $new_log_loc -Force
      $fail_count += 1
    } else {
        # 等待作业完成，并获取输出（包含变量的值）
        $output = Receive-Job $job
        if($output){
          $success_count += 1
        }else{
          $case_name = $test_list[$i+$job_id]
          $fail_test_list += $case_name
          echo "$case_name failed"
          $case_string = $fail_test_list -join "`",`""
          echo "`$test_list=@(`"$case_string`")" > $log_path/fail_gtest_filter.ps1

          $fail_count += 1
        } # end failed_case
    } # end no-time-out case
  } # end for each job
} # end for cases in list

# finish
Write-Progress -Activity "Processing" -Status "Finished" -Completed
if ((Test-Path $log_path/fail)) {
  echo "failed:"
  tree $log_path/fail /f
}

if ((Test-Path $log_path/timeout)) {
  echo "cost time exceed $timeout seconds:"
  tree $log_path/timeout /f
}
$total_cost_time=($now-$start_time).ToString("dd' days 'hh':'mm':'ss")
echo "total cost:"
echo $total_cost_time
$success_count -= $dumb_test_num # acutal success num
echo "fail: $fail_count, success: $success_count"

$host.UI.RawUI.WindowTitle = $test_title
