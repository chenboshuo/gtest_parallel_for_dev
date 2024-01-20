param ($exe_relative_path)

$repeat_time=1

$run_cases="*"
$target_exe= Resolve-Path -Path $exe_relative_path
$timeout = 20*60  # set timeout seconds 
$job_num = 16
$retry_times = 3

# get list if no list is given
$test_list = @()
$get_list_command = "$target_exe" + 
  " --gtest_filter=$run_cases --gtest_list_tests > test_list.txt"
Invoke-Expression $get_list_command
Get-Content "test_list.txt"| ForEach-Object {
  if ($_ -notmatch '^\s') {
    $cur_suite_name = $_
  }else{
    $case_name = $_ -replace '^\s+', ''
    $case_name = $case_name -replace '  #.*$', ''
    $test_list += "$cur_suite_name$case_name"
  }
}

for ($t = 0; $t -lt $retry_times; $t += 1){
  echo "# Round $t">> $GITHUB_STEP_SUMMARY
  $test_time=Get-Date -Format "yyyy-MM-dd HH.mm.ss";
  $log_path=  "./logs/$test_time"
  mkdir -p $log_path > $null
  $log_path= Resolve-Path -Path "./logs/$test_time"

  $test_id=0

  $fail_test_list = New-Object System.Collections.ArrayList
  $start_time=Get-Date
  $fail_count = 0
  $success_count = 0


  # foreach ($case_name in $test_list){
  for ($i = 0; $i -lt $test_list.Count; $i += $job_num) {
    $now=Get-Date

    $test_a_case = {
      param($case_name, $job_id)
      $test_time=Get-Date -Format "yyyy-MM-dd_HH.mm.ss";
      $PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
      $target_command="$using:target_exe" +
        " --gtest_repeat=$using:repeat_time"+
        " --gtest_filter=$case_name" + ";$" + "success=$" + "?"

      $command = {
        Invoke-Expression $target_command >> "$using:log_path/running_$job_id.log";
      }
      $measurements = Measure-Command $command
      $executionTime = $measurements.TotalMilliseconds

      $memoryUsageBytes = (Get-Process -Id $pid).WorkingSet64
      $memoryUsageMB = $memoryUsageBytes / 1MB


      # info
      echo "Test start from $test_time To $(Get-Date -Format "yyyy-MM-dd_HH.mm.ss")" >> $using:log_path/running_$job_id.log 
      echo "time cost: $executionTime ms" >> $using:log_path/running_$job_id.log 
      echo "memory used: $memoryUsageMB MB" >>  $using:log_path/running_$job_id.log 
      
    
      return $success
    } # end test a case

    $jobs = @()
    for($j=0; $j -lt $job_num; $j += 1){
      $job = Start-Job -ScriptBlock $test_a_case -ArgumentList $test_list[$i+$j], $j
      $jobs += $job
    }
    Wait-Job -Job $jobs -Timeout $timeout > $null


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
        $fail_time=Get-Date -Format "yyyy-MM-dd_HH.mm.ss";
        $new_log_loc = "$log_path/timeout/" + $test_list[$i+$job_id] + "_" + $fail_time + ".log"
        $directory = Split-Path $new_log_loc -Parent
        New-Item -ItemType Directory -Path $directory -Force > $null
        mv $log_path/running_$job_id.log $new_log_loc -Force

        # summary for github
        echo "<details><summary> $case_name exceeds $timeout seconds</summary>" >> $GITHUB_STEP_SUMMARY
        echo "" >> $GITHUB_STEP_SUMMARY
        echo "``````" >> $GITHUB_STEP_SUMMARY
        Get-Content "$new_log_loc" >> $GITHUB_STEP_SUMMARY
        echo "``````" >> $GITHUB_STEP_SUMMARY
        echo "" >> $GITHUB_STEP_SUMMARY
        echo "</details>" >> $GITHUB_STEP_SUMMARY
        echo "" >> $GITHUB_STEP_SUMMARY

        $fail_count += 1
      } else {
          # 等待作业完成，并获取输出（包含变量的值）
          $output = Receive-Job $job
          $cur_test_id = $i+$job_id 
          $case_name = $test_list[$cur_test_id]
          $total_test = $test_list.Count
          if($output){
            $success_count += 1
            echo "[(round $t) $cur_test_id/$total_test] $case_name success"
            $end_time=Get-Date
            $new_log_loc = "$log_path/success/" + $case_name + "_" + $test_time + ".log"
            $directory = Split-Path $new_log_loc -Parent
            New-Item -ItemType Directory -Path $directory -Force > $null
            mv "$log_path/running_$job_id.log" $new_log_loc -Force
          }else{
            $case_name = $test_list[$i+$job_id]
            $fail_test_list += $case_name
            $new_log_loc = "$log_path/fail/" + $case_name + "_" + $test_time + ".log"
            echo "[(round $t) $cur_test_id/$total_test] $case_name failed"

            $directory = Split-Path $new_log_loc -Parent
            New-Item -ItemType Directory -Path $directory -Force > $null
            mv "$log_path/running_$job_id.log" $new_log_loc -Force

            # summary for github
            echo "<details><summary> $case_name failed</summary>" >> $GITHUB_STEP_SUMMARY
            echo "" >> $GITHUB_STEP_SUMMARY
            echo "``````" >> $GITHUB_STEP_SUMMARY
            Get-Content "$new_log_loc" >> $GITHUB_STEP_SUMMARY
            echo "``````" >> $GITHUB_STEP_SUMMARY
            echo "" >> $GITHUB_STEP_SUMMARY
            echo "</details>" >> $GITHUB_STEP_SUMMARY
            echo "" >> $GITHUB_STEP_SUMMARY

            $fail_count += 1
          } # end failed_case
      } # end no-time-out case
    } # end for each job
  } # end for cases in list

  $total_cost_time=($now-$start_time).ToString("dd' days 'hh':'mm':'ss")
  echo "- total cost: $total_cost_time" >> $GITHUB_STEP_SUMMARY
  echo "- fail: $fail_count" >> $GITHUB_STEP_SUMMARY
  echo "- success: $success_count" >> $GITHUB_STEP_SUMMARY
  echo "" >> $GITHUB_STEP_SUMMARY

  if($fail_count -eq 0){
    exit 0
  }

  $job_num /= 2
  $wait_time *= 2
  $test_list = $fail_test_list
}


# return success or failure
if($fail_count -eq 0){
  exit 0
}else{
  exit 1
}
