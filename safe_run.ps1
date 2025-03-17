# Set-ExecutionPolicy Unrestricted
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$source_path="Z:\"
$test_name = "cur_release"
$gtest_path = "Z:/bin/googletest-release-1.11.0.zip"
$repeat_time=1
$test_title = $test_name
$log_path="Y:\logs\$test_name"
$fail_filter_path = "$log_path/fail_gtest_filter.ps1"
# $run_cases="SurfSurfInterTest/*:IntersectorCoroutineBatchTests.*Scale*:IntersectorGeometryCoroutineBatchTests.SfSfScale*"
$run_cases="SurfSurfInterTest/*"
# $run_cases="SurfSurfInterTest/*/tol_6"
# $run_cases="SurfSurfInterTest/ConeSpline*"
# $run_cases="SurfSurfInterTest/ConeSpline*/tol_6"
# $run_cases="SurfSurfInterTest/CylinderSpline*"
# $run_cases="SurfSurfInterTest/CylinderSpline*/tol_6"
# $run_cases="SurfSurfInterTest/ConeSpline*:SurfSurfInterTest/CylinderSpline*"
# $run_cases="SurfSurfInterTest/ConeSpline*/tol_6:SurfSurfInterTest/CylinderSpline*/tol_6"
# $run_cases="SurfSurfInterTest/SphereSpline*"
# $run_cases="SurfSurfInterTest/SphereSpline*/tol_6"
# $run_cases="SurfSurfInterTest/SplineSpline*"
# $run_cases="SurfSurfInterTest/SplineSpline*/tol_6"
# $run_cases="SurfSurfInterTest/TorusSpline*"
# $run_cases="SurfSurfInterTest/TorusSpline*/tol_6"

$test_list = @()
# Invoke-Expression ". $fail_filter_path" # get test list from previous tests
# $environment="Debug"
$environment="Release"
$build_path="C:\Users\User\Downloads\$test_name"
$target_exe="$build_path/build/$environment/tests_acis.exe"
$test_time=Get-Date -Format "yyyy-MM-dd HH.mm.ss";
$need_clone=$false
$need_build=$true
$timeout_minutes = @(5, 5, 2, 1) 
$wait_time=1 #wait 1 second
$job_nums = @(8, 32, 8, 4)
$batch_nums = @(64, 1, 1, 1)
$save_cases_time_cost = $false
$retry_times = 2
$repeat_success = $false # filename is the success name
$record_skipped_cases = $true # require set repeat_success=$false

$start_script_time=Get-Date
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
  # cmake
  if(-not(Test-Path "$build_path/build/GME.sln")){
    # update cmake source
    $src_cmake_file = "$source_path\src\test\CMakeLists.txt"
    $src_cmake_file_backup = "$source_path\src\test\CMakeLists_backup.txt"
    while (Test-Path $src_cmake_file_backup) {
        # File still exists, sleep for 1 second
        Start-Sleep -Seconds 1
    }
    cp $src_cmake_file $src_cmake_file_backup
    $raw_url = "https://github.com/google/googletest/archive/release-1.12.1.zip"
    (Get-Content -Path $src_cmake_file -Raw -Encoding UTF8) `
      -replace [regex]::Escape($raw_url), $gtest_path | `
      Set-Content -Path $src_cmake_file -Encoding UTF8 -NoNewline

    $src_acis_cmake_file = "$source_path\src_acis\test\CMakeLists.txt"
    $src_acis_cmake_file_backup = "$source_path\src_acis\test\CMakeLists_backup.txt"
    cp $src_acis_cmake_file $src_acis_cmake_file_backup
    (Get-Content -Path $src_acis_cmake_file -Raw -Encoding UTF8) `
      -replace [regex]::Escape($raw_url), $gtest_path | `
      Set-Content -Path $src_acis_cmake_file -Encoding UTF8 -NoNewline

    $host.UI.RawUI.WindowTitle = "$test_title[cmake configing]"
    cmake -G "Visual Studio 17 2022"  `
      -S "$source_path" -B "$build_path/build" `
      -DCMAKE_C_FLAGS="/utf-8" -DCMAKE_CXX_FLAGS="/utf-8"

    # restore cmake
    rm $src_cmake_file
    mv $src_cmake_file_backup $src_cmake_file 
    rm $src_acis_cmake_file
    mv $src_acis_cmake_file_backup $src_acis_cmake_file
  }

  # build
  $host.UI.RawUI.WindowTitle = "$test_title[building]"
  if (Test-Path $target_exe) {
    rm $target_exe
  }
  MSBuild $build_path/build/GME.sln  -target:gme_acis\tests_acis -property:Configuration=$environment;
}

if(-not (Test-Path -Path $target_exe)){
  $host.UI.RawUI.WindowTitle = "$test_title[error]"
  # Prompt the user for confirmation
  $response = Read-Host "Type 'y' to delete generated sln"

  # Check the user's input
  if ($response -eq 'y') {
      # Add your action here
      rm "$build_path/build/GME.sln"
      echo "sln deleted"
  } else {
      Write-Host "Action canceled."
  }
  exit 1
}


# store diff
$cur=pwd
cd $source_path
git config --global --add safe.directory '%(prefix)///VBoxSvr/GME/'
git log --max-count=300 --pretty=format:"%h - %an, %ad : %s" --date=iso-local > $log_path/git.log
git diff > $log_path/change.patch
cd $cur
$build_finish_time=Get-Date

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
$all_cases_num = $test_list.Count
$build_finish_time=Get-Date

# run
$host.UI.RawUI.WindowTitle = "$test_title[$job_num jobs run]"

# 创建进度条
$progress = @{
    Activity = "test_all"
    CurrentOperation = "start"
    Status = "running"
    PercentComplete = 0
}

$start_time=Get-Date
for ($t = 0; $t -lt $retry_times; $t += 1){
  Write-Progress @progress
  $test_id=0
  $fail_test_list = New-Object System.Collections.ArrayList
  $round_start_time=Get-Date
  $fail_count = 0
  $success_count = 0
  $dumb_test_num = 0
  $job_num = $job_nums[$t]
  $batch_num = $batch_nums[$t]
  $timeout = $timeout_minutes[$t] * 60

  $host.UI.RawUI.WindowTitle = "$test_title[$($t+1)/$retry_times $job_num * $batch_num]"

  while ($test_list.Count % $job_num*$batch_num -ne 0){
    $test_list += "dumb_test_$dumb_test_num"
    $dumb_test_num += 1
  }

  for ($i = 0; $i -lt $test_list.Count; $i += $job_num*$batch_num) {
    $now=Get-Date

    $test_a_batch = {
      param($case_name, $job_id)
      $test_time=Get-Date -Format "yyyy-MM-dd_HH.mm.ss";
      $PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
      $target_command="$using:build_path/build/$using:environment/tests_acis.exe" +
        " --gtest_repeat=$using:repeat_time"+
        " --gtest_fail_fast" +
        " --gtest_filter=$case_name" + ";$" + "success=$" + "?"

      if($save_cases_time_cost){
        $command = {
          Invoke-Expression $target_command >> $using:log_path/running_$job_id.log;
        }
        $measurements = Measure-Command $command
        $executionTime = $measurements.TotalMilliseconds

        $memoryUsageBytes = (Get-Process -Id $pid).WorkingSet64
        $memoryUsageMB = $memoryUsageBytes / 1MB


        # info
        echo "Test start from $test_time To $(Get-Date -Format "yyyy-MM-dd_HH.mm.ss")" >>  $using:log_path/running_$job_id.log 
        echo "time cost: $executionTime ms" >> $using:log_path/running_$job_id.log 
        echo "memory used: $memoryUsageMB MB" >>  $using:log_path/running_$job_id.log 
      }else{
        Invoke-Expression $target_command >> $using:log_path/running_$job_id.log;
      }
     
      $end_time=Get-Date
      $name_list = $case_name.Split(":")
      if($success){ # success
        $new_log_loc = $using:log_path + "/success/";
      }else{
        $new_log_loc = $using:log_path + "/fail_$using:batch_num" + "_batch_cases/";
      }
      $selectedNames = if ($using:repeat_success -or (-not $success)) { 
        $name_list 
      } else { $name_list[0] }
      foreach ($single_name in $selectedNames) {
        $full_path = "$new_log_loc$single_name`_$test_time.log"
        $directory = Split-Path $full_path -Parent
        New-Item -ItemType Directory -Path $directory -Force > $null
        cp "$using:log_path/running_$job_id.log" $full_path -Force
      }
      rm $using:log_path/running_$job_id.log
      return $success
    } # end test a case

    $jobs = @()
    for($j=0; $j -lt $job_num; $j += 1){
      $batch_list = $test_list[($i+$j*$batch_num)..($i+($j+1)*$batch_num - 1)] -join ":"
      $job = Start-Job -ScriptBlock $test_a_batch -ArgumentList $batch_list, $j
      $jobs += $job
    }
    Wait-Job -Job $jobs -Timeout $timeout > $null

    # update progress
    $total_cost_time=($now-$round_start_time).ToString("dd' days 'hh':'mm':'ss")
    $progress.CurrentOperation = $test_list[$i .. ($i+$job_num-1)] -join ", " 
    
    $percent=($test_id / $test_list.Count) * 100
    $progress.PercentComplete = $percent 
    $progress.Status = "[$($t+1)/$retry_times] fail: $fail_count, success: $success_count [$total_cost_time] | $percent %"
    Write-Progress @progress
    $test_id += $job_num*$batch_num

    # 等待作业完成或超时
    # foreach($job in $jobs){
    for($job_id=0; $job_id -lt $job_num; $job_id +=1){
      $job = $jobs[$job_id]
      if ($job.State -eq 'Running') {
        # 如果超时，终止作业
        Stop-Job -Job $job
        Remove-Job $job
        $case_list = $test_list[($i+$job_id*$batch_num)..($i+($job_id+1)*$batch_num-1)]
        echo "$case_list batch time exceed $timeout seconds."
        $fail_test_list += $case_list
        $case_string = $fail_test_list -join "`",`""
        echo "`$test_list=@(`"$case_string`")" > $log_path/fail_gtest_filter.ps1
        $fail_time=Get-Date -Format "yyyy-MM-dd_HH.mm.ss";
        foreach($single_case in $case_list){
          $new_log_loc = $log_path + "/timeout/" + $single_case + "_" + $fail_time + ".log"
          $directory = Split-Path $new_log_loc -Parent
          New-Item -ItemType Directory -Path $directory -Force > $null
          cp $log_path/running_$job_id.log $new_log_loc -Force
        }
        rm $log_path/running_$job_id.log 
        $fail_count += $batch_count
      } else {
          # 等待作业完成，并获取输出（包含变量的值）
          $output = Receive-Job $job
          Remove-Job $job
          if($output){
            $success_count += $batch_num
          }else{
            $case_list = $test_list[($i+$job_id*$batch_num)..($i+($job_id+1)*$batch_num - 1)]
            $fail_test_list += $case_list
            echo "$case_list failed"
            $case_string = $fail_test_list -join "`",`""
            echo "`$test_list=@(`"$case_string`")" > $log_path/fail_gtest_filter.ps1

            $fail_count += $batch_num
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

  function show_and_save {
      param (
          [string] $Message
      )
      $Message | Tee-Object -FilePath "$log_path/summary_round_$t.log"  -Append
  }

  echo "round $($t+1): "
  $total_cost_time=($now-$round_start_time).ToString("dd' days 'hh':'mm':'ss")
  show_and_save "running $run_cases"
  show_and_save "total cost: $total_cost_time (with $batch_num batch and $job_num jobs)"
  $success_count -= $dumb_test_num # acutal success num
  $case_count=($fail_count+$success_count)
  show_and_save "tested $case_count cases"
  show_and_save "fail: $fail_count, success: $success_count"
  show_and_save "fail_rate: $(100*$fail_count / $case_count) %" 
  show_and_save "success_rate: $(100*$success_count / $case_count) %"

  $test_list = $fail_test_list
}

function show_and_save {
    param (
        [string] $Message
    )
    $Message | Tee-Object -FilePath "$log_path/summary.log"  -Append
}

echo ""
$running_cost_time=($now-$start_time).ToString("dd' days 'hh':'mm':'ss")
show_and_save "running $run_cases"
show_and_save "running cost: $running_cost_time (with retry $retry_times)"
$script_cost_time=($now-$start_script_time).ToString("dd' days 'hh':'mm':'ss")
$build_cost=($build_finish_time-$start_script_time).ToString("dd' days 'hh':'mm':'ss")
show_and_save "all cost: $script_cost_time (building cost $build_cost)"
show_and_save "tested $all_cases_num cases"
$success_count = $all_cases_num - $fail_count
show_and_save "fail: $fail_count, success: $success_count"
show_and_save "fail_rate: $(100*$fail_count / $all_cases_num) %" 
show_and_save "success_rate: $(100*$success_count / $all_cases_num) %"

foreach($fail_case in $fail_test_list){
  echo "$fail_case failed"
}

if($record_skipped_cases){
  $success_path = "$log_path/success"
  $success_files = Get-ChildItem -Path $log_path -Recurse -File -Filter "*.log"
  $skipped_cases = @()
  foreach ($success_file in $success_files) {
    # Read the file and extract skipped test names
    $skipped_tests = Get-Content $success_file.FullName |
        Where-Object { $_ -match '\[  SKIPPED \] (.+) \(' } |
        ForEach-Object { $matches[1] }
    # match example:  [  SKIPPED ] SurfSurfInterTest/ConeSpline.Case1/tol_8 (2 ms)
    # use left pathess ( to make the match unique

    # Add extracted test names to the list
    $skipped_cases += $skipped_tests
    echo $matches[1]
  }
  # Remove duplicates
  $skipped_cases = $skipped_cases | Sort-Object -Unique
  echo $skipped_cases
  $skipped_cases | 
    ForEach-Object { [PSCustomObject]@{ Value = $_ } } |
    Export-Csv -Path $log_path/skipped_list.csv -NoTypeInformation
}

$host.UI.RawUI.WindowTitle = $test_title
