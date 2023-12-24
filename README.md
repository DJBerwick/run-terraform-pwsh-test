# Run terraform init and plan

```powershell
./Run-Terraform.ps1 `
-RunTerraformInit 'true' `
-RunTerraformPlan 'true' `
-BackendStorageSubscriptionId $Env:BACKEND_STORAGE_SUBSCRIPTION_ID `
-BackendStorageAccountName $Env:BACKEND_STORAGE_ACCOUNT_NAME `
-LzName "bakery" `
-StackName "subscription"
```

# Run terraform init and plan and apply

```powershell
./Run-Terraform.ps1 `
-RunTerraformInit 'true' `
-RunTerraformPlan 'true' `
-RunTerraformApply 'true' `
-BackendStorageSubscriptionId $Env:BACKEND_STORAGE_SUBSCRIPTION_ID `
-BackendStorageAccountName $Env:BACKEND_STORAGE_ACCOUNT_NAME `
-LzName "bakery" `
-StackName "subscription"
```

# Run terraform init, plan destroy and destroy
```powershell
./Run-Terraform.ps1 `
-RunTerraformInit 'true' `
-RunTerraformPlanDestroy 'true' `
-RunTerraformDestroy 'true'
-BackendStorageSubscriptionId $Env:BACKEND_STORAGE_SUBSCRIPTION_ID `
-BackendStorageAccountName $Env:BACKEND_STORAGE_ACCOUNT_NAME `
-LzName "bakery" `
-StackName "subscription"
```


# Run terraform init and plan using PowerShell bools rather than conversion

```powershell
./Run-Terraform.ps1 `
-RunTerraformInit $true `
-RunTerraformPlan $true `
-BackendStorageSubscriptionId $Env:BACKEND_STORAGE_SUBSCRIPTION_ID `
-BackendStorageAccountName $Env:BACKEND_STORAGE_ACCOUNT_NAME `
-LzName "bakery" `
-StackName "subscription"
```
