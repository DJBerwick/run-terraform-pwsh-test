param (
    [string]$RunTerraformInit = "true",
    [string]$RunTerraformPlan = "true",
    [string]$RunTerraformPlanDestroy = "false",
    [string]$RunTerraformApply = "false",
    [string]$RunTerraformDestroy = "false",
    [bool]$DebugMode = $false,
    [string]$DeletePlanFiles = "true",
    [string]$TerraformVersion = "latest",

    [Parameter(Mandatory = $true)]
    [string]$BackendStorageSubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$BackendStorageAccountName,

    [Parameter(Mandatory = $true)]
    [string]$LzName,

    [Parameter(Mandatory = $true)]
    [string]$StackName
)

try
{
    $ErrorActionPreference = 'Stop'
    $CurrentWorkingDirectory = (Get-Location).path

    # Enable debug mode if DebugMode is set to $true
    if ($DebugMode)
    {
        $DebugPreference = "Continue"
        $Env:TF_LOG = "DEBUG"
    }
    else
    {
        $DebugPreference = "SilentlyContinue"
    }


    function Convert-ToBoolean($value)
    {
        $valueLower = $value.ToLower()
        if ($valueLower -eq "true")
        {
            return $true
        }
        elseif ($valueLower -eq "false")
        {
            return $false
        }
        else
        {
            throw "[$( $MyInvocation.MyCommand.Name )] Error: Invalid value - $value. Exiting."
            exit 1
        }
    }

    # Function to check if Tfenv is installed
    function Test-TfenvExists
    {
        try
        {
            $tfenvPath = Get-Command tfenv -ErrorAction Stop
            Write-Host "[$( $MyInvocation.MyCommand.Name )] Success: Tfenv found at: $( $tfenvPath.Source )" -ForegroundColor Green
        }
        catch
        {
            Write-Warning "[$( $MyInvocation.MyCommand.Name )] Warning: Tfenv is not installed or not in PATH. Skipping version checking."
        }
    }

    # Function to check if Terraform is installed
    function Test-TerraformExists
    {
        try
        {
            $terraformPath = Get-Command terraform -ErrorAction Stop
            Write-Host "[$( $MyInvocation.MyCommand.Name )] Success: Terraform found at: $( $terraformPath.Source )" -ForegroundColor Green
        }
        catch
        {
            throw "[$( $MyInvocation.MyCommand.Name )] Error: Terraform is not installed or not in PATH. Exiting."
            exit 1
        }
    }

    function Get-StackDirectory
    {
        param (
            [string]$StackName,
            [string]$CurrentWorkingDirectory
        )

        # Scan the 'stacks' directory and create a mapping
        $folderMap = @{ }
        $StacksFolderName = "stacks" # This shouldn't really ever change
        $StacksFullPath = Join-Path -Path $CurrentWorkingDirectory -ChildPath $StacksFolderName
        Set-Location $StacksFullPath
        Get-ChildItem -Path $StacksFullPath -Directory | ForEach-Object {
            $folderNumber = $_.Name.Split('_')[0]
            Write-Debug "[$( $MyInvocation.MyCommand.Name )] Debug: Folder number is $folderNumber"
            $folderName = $_.Name.Split('_')[1]
            $folderMap[$folderName.ToLower()] = $_.Name
        }

        $targetFolder = $folderMap[$StackName.ToLower()]
        $CalculatedPath = Join-Path -Path $StacksFullPath -ChildPath $targetFolder
        Write-Debug "[$( $MyInvocation.MyCommand.Name )] Debug: targetFolder is $targetFolder"
        if ($null -ne $targetFolder)
        {
            Write-Host "[$( $MyInvocation.MyCommand.Name )] Success: Stack directory found, changing to folder: $CalculatedPath" -ForegroundColor Green
            Set-Location $CalculatedPath
        }
        else
        {
            throw "[$( $MyInvocation.MyCommand.Name )] Error: Invalid folder selection"
            exit 1
        }
    }

    function Get-GitBranch
    {
        try
        {
            # Get the current Git branch name
            $branchName = (git rev-parse --abbrev-ref HEAD).toLower()

            # Check if the command was successful
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branchName))
            {
                throw "[$( $MyInvocation.MyCommand.Name )] Error: Failed to get the current Git branch."
            }

            # Determine the workspace name based on the branch name
            $workspace = if ($branchName -eq "main" -or $branchName -eq "master")
            {
                "prd"
            }
            else
            {
                $branchName
            }

            Write-Debug "[$( $MyInvocation.MyCommand.Name )] Debug: Git branch determined as: $workspace"
            return $workspace
        }
        catch
        {
            throw "[$( $MyInvocation.MyCommand.Name )] Error encountered: $_"
            exit 1
        }
    }

    function Select-TerraformWorkspace
    {
        param (
            [string]$Workspace
        )

        # Try to create a new workspace or select it if it already exists
        terraform workspace new $Workspace
        if ($LASTEXITCODE -eq 0)
        {
            Write-Host "[$( $MyInvocation.MyCommand.Name )] Success: Successfully created and selected the Terraform workspace '$Workspace'." -ForegroundColor Green
            return $Workspace
        }
        else
        {
            terraform workspace select $Workspace 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0)
            {
                Write-Host "[$( $MyInvocation.MyCommand.Name )] Success: Successfully selected the existing Terraform workspace '$Workspace'." -ForegroundColor Green
                return $Workspace
            }
            else
            {
                throw "[$( $MyInvocation.MyCommand.Name )] Error: Failed to select the existing Terraform workspace '$Workspace'."
                exit 1
            }
        }
    }

    function Invoke-TerraformInit
    {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$BackendStorageSubscriptionId,

            [Parameter(Mandatory = $true)]
            [string]$BackendStorageAccountName,

            [Parameter(Mandatory = $true)]
            [string]$LzName,

            [Parameter(Mandatory = $true)]
            [string]$Workspace,

            [Parameter(Mandatory = $true)]
            [string]$WorkingDirectory
        )

        Begin
        {
            # Initial setup and variable declarations
            Write-Debug "[$( $MyInvocation.MyCommand.Name )] Debug: Initializing Terraform..."
            $Env:TF_VAR_lz_name = $LzName.ToLower()
            $BackendStorageAccountBlobContainerName = "tfstate-$Workspace-$LzName-uksouth"
        }

        Process
        {
            try
            {
                # Change to the specified working directory
                Set-Location -Path $WorkingDirectory

                # Construct the backend config parameters
                $backendConfigParams = @(
                    "-backend-config=subscription_id=$BackendStorageSubscriptionId",
                    "-backend-config=storage_account_name=$BackendStorageAccountName",
                    "-backend-config=container_name=$BackendStorageAccountBlobContainerName"
                )

                Write-Debug "[$( $MyInvocation.MyCommand.Name )] Debug: Backend config params are: $backendConfigParams"

                # Run terraform init with the constructed parameters
                terraform init @backendConfigParams | Out-Host
                Write-Debug "[$( $MyInvocation.MyCommand.Name )] Debug: Last exit code is $LASTEXITCODE"
                # Check if terraform init was successful
                if ($LASTEXITCODE -ne 0)
                {
                    throw "[$( $MyInvocation.MyCommand.Name )] Error: Terraform init failed with exit code $LASTEXITCODE"
                    exit 1
                }
            }
            catch
            {
                throw "[$( $MyInvocation.MyCommand.Name )] Error: Terraform init failed with exception: $_"
                exit 1
            }
        }

        End
        {
            Write-Debug "[$( $MyInvocation.MyCommand.Name )] Debug: Terraform initialization completed."
        }
    }


    function Invoke-TerraformPlan
    {
        [CmdletBinding()]
        param (
            [string]$WorkingDirectory = $WorkingDirectory,
            [bool]$RunTerraformPlan = $true
        )

        Begin {
            Write-Debug "[$( $MyInvocation.MyCommand.Name )] Begin: Initializing Terraform Plan in $WorkingDirectory"
        }

        Process {
            if ($RunTerraformPlan)
            {
                Write-Host "[$( $MyInvocation.MyCommand.Name )] Info: Running Terraform Plan in $WorkingDirectory" -ForegroundColor Green
                try
                {
                    Set-Location -Path $WorkingDirectory
                    terraform plan -out tfplan.plan | Out-Host

                    if (Test-Path tfplan.plan)
                    {
                        terraform show -json tfplan.plan | Tee-Object -FilePath tfplan.json | Out-Null
                    }
                    else
                    {
                        throw "[$( $MyInvocation.MyCommand.Name )] Error: Terraform plan file not created"
                        exit 1
                    }
                }
                catch
                {
                    throw "[$( $MyInvocation.MyCommand.Name )] Error encountered during Terraform plan: $_"
                    exit 1
                }
            }
        }

        End {
            Write-Debug "[$( $MyInvocation.MyCommand.Name )] End: Completed Terraform Plan execution"
        }
    }


    # Function to execute Terraform plan for destroy
    function Invoke-TerraformPlanDestroy
    {
        [CmdletBinding()]
        param (
            [string]$WorkingDirectory = $WorkingDirectory,
            [bool]$RunTerraformPlanDestroy = $true
        )

        Begin {
            Write-Debug "[$( $MyInvocation.MyCommand.Name )] Begin: Preparing to execute Terraform Plan Destroy in $WorkingDirectory"
        }

        Process {
            if ($RunTerraformPlanDestroy)
            {
                try
                {
                    Write-Host "[$( $MyInvocation.MyCommand.Name )] Info: Running Terraform Plan Destroy in $WorkingDirectory" -ForegroundColor Yellow
                    Set-Location -Path $WorkingDirectory
                    terraform plan -destroy -out tfplan.plan | Out-Host

                    if (Test-Path tfplan.plan)
                    {
                        terraform show -json tfplan.plan | Tee-Object -FilePath tfplan.json | Out-Null
                    }
                    else
                    {
                        throw "[$( $MyInvocation.MyCommand.Name )] Error: Terraform plan file not created"
                        exit 1
                    }
                }
                catch
                {
                    throw  "[$( $MyInvocation.MyCommand.Name )] Error encountered during Terraform Plan Destroy: $_"
                    exit 1
                }
            }
            else
            {
                throw  "[$( $MyInvocation.MyCommand.Name )] Error encountered during Terraform Plan Destroy or internal script error occured: $_"
                exit 1
            }
        }

        End {
            Write-Debug "[$( $MyInvocation.MyCommand.Name )] End: Completed execution of Terraform Plan Destroy"
        }
    }

    # Function to execute Terraform apply
    function Invoke-TerraformApply
    {
        if ($RunTerraformApply -eq $true)
        {
            try
            {
                Write-Host "[$( $MyInvocation.MyCommand.Name )] Info: Running Terraform Apply in $WorkingDirectory" -ForegroundColor Yellow
                if (Test-Path tfplan.plan)
                {
                    terraform apply -auto-approve tfplan.plan | Out-Host
                }
                else
                {
                    throw "[$( $MyInvocation.MyCommand.Name )] Error: Terraform plan file not present for terraform apply"
                    return $false
                }
            }
            catch
            {
                throw "[$( $MyInvocation.MyCommand.Name )] Error: Terraform Apply failed"
                return $false
            }
        }
    }

    # Function to execute Terraform destroy
    function Invoke-TerraformDestroy
    {
        if ($RunTerraformDestroy -eq $true)
        {
            try
            {
                Write-Host "[$( $MyInvocation.MyCommand.Name )] Info: Running Terraform Destroy in $WorkingDirectory" -ForegroundColor Yellow
                if (Test-Path tfplan.plan)
                {
                    terraform apply -auto-approve tfplan.plan | Out-Host
                }
                else
                {
                    throw "[$( $MyInvocation.MyCommand.Name )] Error: Terraform plan file not present for terraform destroy"
                    return $false
                }
            }
            catch
            {
                throw "[$( $MyInvocation.MyCommand.Name )] Error: Terraform Destroy failed"
                return $false
            }
        }
    }

    # Convert string parameters to boolean
    $ConvertedRunTerraformInit = Convert-ToBoolean $RunTerraformInit
    $ConvertedRunTerraformPlan = Convert-ToBoolean $RunTerraformPlan
    $ConvertedRunTerraformPlanDestroy = Convert-ToBoolean $RunTerraformPlanDestroy
    $ConvertedRunTerraformApply = Convert-ToBoolean $RunTerraformApply
    $ConvertedRunTerraformDestroy = Convert-ToBoolean $RunTerraformDestroy
    $ConvertedDeletePlanFiles = Convert-ToBoolean $DeletePlanFiles


    # Diagnostic output
    Write-Debug "[$( $MyInvocation.MyCommand.Name )] Debug: LzName: $LzName"
    Write-Debug "[$( $MyInvocation.MyCommand.Name )] Debug: ConvertedRunTerraformInit: $ConvertedRunTerraformInit"
    Write-Debug "[$( $MyInvocation.MyCommand.Name )] Debug: ConvertedRunTerraformPlan: $ConvertedRunTerraformPlan"
    Write-Debug "[$( $MyInvocation.MyCommand.Name )] Debug: ConvertedRunTerraformPlanDestroy: $ConvertedRunTerraformPlanDestroy"
    Write-Debug "[$( $MyInvocation.MyCommand.Name )] Debug: ConvertedRunTerraformApply: $ConvertedRunTerraformApply"
    Write-Debug "[$( $MyInvocation.MyCommand.Name )] Debug: ConvertedRunTerraformDestroy: $ConvertedRunTerraformDestroy"
    Write-Debug "[$( $MyInvocation.MyCommand.Name )] Debug: DebugMode: $DebugMode"
    Write-Debug "[$( $MyInvocation.MyCommand.Name )] Debug: ConvertedDeletePlanFiles: $ConvertedDeletePlanFiles"


    # Chicken and Egg checker
    if (-not$ConvertedRunTerraformInit -and ($ConvertedRunTerraformPlan -or $ConvertedRunTerraformPlanDestroy -or $ConvertedRunTerraformApply -or $ConvertedRunTerraformDestroy))
    {
        throw "[$( $MyInvocation.MyCommand.Name )] Error: Terraform init must be run before executing plan, plan destroy, apply, or destroy commands."
        exit 1
    }

    if ($ConvertedRunTerraformPlan -eq $true -and $ConvertedRunTerraformPlanDestroy -eq $true)
    {
        throw "[$( $MyInvocation.MyCommand.Name )] Error: Both Terraform Plan and Terraform Plan Destroy cannot be true at the same time"
        exit 1
    }

    if ($ConvertedRunTerraformApply -eq $true -and $ConvertedRunTerraformDestroy -eq $true)
    {
        throw "[$( $MyInvocation.MyCommand.Name )] Error: Both Terraform Apply and Terraform Destroy cannot be true at the same time"
        exit 1
    }

    if ($ConvertedRunTerraformPlan -eq $false -and $ConvertedRunTerraformApply -eq $true)
    {
        throw "[$( $MyInvocation.MyCommand.Name )] Error: You must run terraform plan and terraform apply together to use this script"
        exit 1
    }

    if ($ConvertedRunTerraformPlanDestroy -eq $false -and $ConvertedRunTerraformDestroy -eq $true)
    {
        throw "[$( $MyInvocation.MyCommand.Name )] Error: You must run terraform plan destroy and terraform destroy together to use this script"
        exit 1
    }

    try
    {
        # Initial Terraform setup
        Test-TfenvExists
        Test-TerraformExists

        Get-StackDirectory -StackName $StackName -CurrentWorkingDirectory $CurrentWorkingDirectory
        $WorkingDirectory = (Get-Location).Path

        $Workspace = Get-GitBranch
        if (-not$Workspace)
        {
            throw "[$( $MyInvocation.MyCommand.Name )] Error: Failed to determine Git branch for workspace."
        }

        # Terraform Init and Workspace Selection
        if ($ConvertedRunTerraformInit)
        {
            Invoke-TerraformInit `
                -WorkingDirectory $WorkingDirectory `
                -BackendStorageAccountName $BackendStorageAccountName `
                -BackendStorageSubscriptionId $BackendStorageSubscriptionId `
                -Workspace $Workspace -LzName $LzName
            $InvokeTerraformInitSuccessful = ($LASTEXITCODE -eq 0)
        }
        else
        {
            throw "[$( $MyInvocation.MyCommand.Name )] Error: Terraform initialization failed."
        }

        if (-not(Select-TerraformWorkspace -Workspace $Workspace))
        {
            throw "[$( $MyInvocation.MyCommand.Name )] Error: Failed to select Terraform workspace."
        }

        # Conditional execution based on parameters
        if ($InvokeTerraformInitSuccessful -and $ConvertedRunTerraformPlan -and -not$ConvertedRunTerraformPlanDestroyonvRunTerraformPlanDestroy)
        {
            Invoke-TerraformPlan -WorkingDirectory $WorkingDirectory
            $InvokeTerraformPlanSuccessful = ($LASTEXITCODE -eq 0)
        }

        if ($InvokeTerraformInitSuccessful -and $ConvertedRunTerraformPlanDestroy -and -not$ConvertedRunTerraformPlan)
        {
            Invoke-TerraformPlanDestroy -WorkingDirectory $WorkingDirectory
            $InvokeTerraformPlanDestroySuccessful = ($LASTEXITCODE -eq 0)

        }

        if ($InvokeTerraformInitSuccessful -and $ConvertedRunTerraformApply -and $InvokeTerraformPlanSuccessful)
        {
            Invoke-TerraformApply
            $InvokeTerraformApplySuccessful = ($LASTEXITCODE -eq 0)
            if (-not$InvokeTerraformApplySuccessful)
            {
                throw "[$( $MyInvocation.MyCommand.Name )] Error: An error occured during terraform apply command"
                exit 1
            }
        }

        if ($ConvertedRunTerraformDestroy -and $InvokeTerraformPlanDestroySuccessful)
        {
            Invoke-TerraformDestroy
            $InvokeTerraformDestroySuccessful = ($LASTEXITCODE -eq 0)

            if (-not$InvokeTerraformDestroySuccessful)
            {
                throw "[$( $MyInvocation.MyCommand.Name )] Error: An error occured during terraform destroy command"
                exit 1
            }
        }
    }
    catch
    {
        throw "[$( $MyInvocation.MyCommand.Name )] Error: in script execution: $_"
        exit 1
    }

}
catch
{
    throw "[$( $MyInvocation.MyCommand.Name )] Error: An error has occured in the script:  $_"
    exit 1
}

finally
{
    if ($DeletePlanFiles -eq $true)
    {
        $planFile = "tfplan.plan"
        if (Test-Path $planFile)
        {
            Remove-Item -Path $planFile -Force -ErrorAction Stop
            Write-Debug "[$( $MyInvocation.MyCommand.Name )] Debug: Deleted $planFile"
        }
        $planJson = "tfplan.json"
        if (Test-Path $planJson)
        {
            Remove-Item -Path $planJson -Force -ErrorAction Stop
            Write-Debug "[$( $MyInvocation.MyCommand.Name )] Debug: Deleted $planJson"
        }
    }
    Set-Location $CurrentWorkingDirectory
}
