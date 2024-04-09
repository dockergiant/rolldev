# Setup Admin Auto Login in Magento 2



Enabling admin auto-login in Magento 2 can be a great time-saver for developers. By setting a specific environment variable and using a command-line tool, you can bypass the manual login process. This guide will walk you through enabling this feature safely in a development environment.

#### Prerequisites

- Access to the command line or terminal.
- Administrative access to your Magento 2 project files.
- The `roll` command-line tool installed in your development environment.

#### Step 1: Configure Your Environment File

1. **Locate Your `.env.roll` File**: This file should be in the root of your Magento 2 project.

2. **Set the ROLL_ADMIN_AUTOLOGIN Variable**:
    - Open the `.env.roll` file in your text editor.
    - Add or modify the following line:
      ```
      ROLL_ADMIN_AUTOLOGIN=1
      ```
    - Save the changes. This tells the auto-login mechanism to activate within your development environment.
3. restart containers by executing this in your project root
   ```
    roll env up
   ```

#### Step 2: Generate a Local User for Auto-Login

1. **Open Your Terminal**: Navigate to the root directory of your Magento 2 project.

2. **Run the Setup Command**: Execute the following command:
    ```
    roll setup-autologin
    ```
   This command generates a local user in your Magento 2 database, configured for auto-login. Follow any prompts to complete the setup, which may involve specifying a username or password, though typically it will create a default user for you.

#### Step 3: Verify Auto-Login Functionality

- After completing the setup, navigate to your Magento 2 admin URL in your web browser. If configured correctly, you should be logged into the admin dashboard automatically without the need to enter login credentials.

#### Step 4: Disable Auto-Login (Important for Production)

- **For Security Reasons**: Remember to disable this feature before moving your project to a staging or production environment. You can disable it by setting:
  ```
  ROLL_ADMIN_AUTOLOGIN=0
  ```
  in your `.env.roll` file, then running any necessary deployment commands for your environment.

#### Security Considerations

- **Development Only**: This auto-login method should only be used in a local or secure development environment. Never use or enable auto-login in production, as it poses a significant security risk.
- **Access Control**: Ensure that your development environment is not accessible from the internet or by unauthorized users.

This tutorial assumes you're familiar with basic Magento 2 and shell/command line operations. Adjustments may be necessary based on your specific development setup or Magento version. Always consult your development team or Magento documentation for best practices tailored to your project.