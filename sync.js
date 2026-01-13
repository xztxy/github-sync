const simpleGit = require('simple-git');
const { Octokit } = require('@octokit/rest');
const fs = require('fs');
const path = require('path');

// 配置文件路径
const CONFIG_FILE_PATH = path.join(__dirname, 'sync-config.json');

// 从配置文件或环境变量获取配置
let sourceRepos = [];
let configSource = 'environment variables';

// 首先尝试从配置文件读取
if (fs.existsSync(CONFIG_FILE_PATH)) {
  try {
    const configContent = fs.readFileSync(CONFIG_FILE_PATH, 'utf8');
    const config = JSON.parse(configContent);
    sourceRepos = config.sourceRepos || [];
    configSource = 'configuration file';
    console.log(`📄 Loaded configuration from ${CONFIG_FILE_PATH}`);
  } catch (error) {
    console.error(`⚠️  Failed to read configuration file: ${error.message}`);
    console.error('   Falling back to environment variables');
  }
}

// 如果配置文件未提供有效配置，从环境变量获取
if (!Array.isArray(sourceRepos) || sourceRepos.length === 0) {
  sourceRepos = process.env.SOURCE_REPOS ? JSON.parse(process.env.SOURCE_REPOS) : [];
  configSource = 'environment variables';
}

// 使用当前仓库作为目标仓库，GitHub Actions自动提供GITHUB_REPOSITORY环境变量
const targetRepo = process.env.TARGET_REPO || process.env.GITHUB_REPOSITORY;
const githubToken = process.env.GITHUB_TOKEN;

// 验证配置
if (!Array.isArray(sourceRepos) || sourceRepos.length === 0) {
  console.error('Error: SOURCE_REPOS must be a non-empty array');
  console.error('Please either:');
  console.error('  1. Create sync-config.json file with sourceRepos array, or');
  console.error('  2. Set SOURCE_REPOS environment variable with proper JSON format');
  process.exit(1);
}

if (!targetRepo || !githubToken) {
  console.error('Error: Missing required environment variables');
  if (!targetRepo) {
    console.error('  - TARGET_REPO: Not provided and GITHUB_REPOSITORY is not available (are you running in GitHub Actions?)');
  }
  if (!githubToken) {
    console.error('  - GITHUB_TOKEN: Please set this environment variable');
  }
  process.exit(1);
}

console.log('Starting repository sync...');
console.log(`Config Source: ${configSource}`);
console.log(`Target Repo: ${targetRepo}`);
console.log(`Source Repos Count: ${sourceRepos.length}`);
console.log('Source Repos:');
sourceRepos.forEach((repo, index) => {
  console.log(`  ${index + 1}. ${repo.repoName}: ${repo.repoUrl} (${repo.sourceBranch}) -> ${repo.targetBranch}`);
});

// 初始化 Octokit
const octokit = new Octokit({
  auth: githubToken
});

// 主同步函数
const syncRepositories = async () => {
  try {
    // 遍历每个源仓库
    for (const repoConfig of sourceRepos) {
      const {
        repoUrl,
        sourceBranch = 'main',
        targetBranch = path.basename(repoUrl, '.git'),
        repoName = path.basename(repoUrl, '.git')
      } = repoConfig;

      console.log(`\n🔄 Processing repository: ${repoName}`);
      console.log(`   Source: ${repoUrl} (${sourceBranch})`);
      console.log(`   Target: ${targetRepo} (${targetBranch})`);

      // 为每个仓库创建独立的临时目录
      const tempDir = path.join(__dirname, 'temp', repoName);
      
      // 确保临时目录存在
      if (!fs.existsSync(tempDir)) {
        fs.mkdirSync(tempDir, { recursive: true });
      }

      // 克隆源仓库
      console.log(`   Cloning repository: ${repoUrl}`);
      let git = simpleGit();
      let actualSourceBranch = sourceBranch;
      
      try {
        // 尝试使用指定分支克隆
        await git.clone(repoUrl, tempDir, {
          '--single-branch': true,
          '--branch': actualSourceBranch
        });
      } catch (cloneError) {
        if (cloneError.message.includes('Remote branch') && cloneError.message.includes('not found')) {
          console.log(`   ⚠️  Branch ${actualSourceBranch} not found, trying to get default branch`);
          
          // 解析仓库所有者和名称
          // Handle URLs with or without .git suffix
          const repoMatch = repoUrl.match(/https:\/\/github\.com\/(.*?)\/(.*?)(?:\.git)?$/);
          if (repoMatch) {
            const [, owner, repo] = repoMatch;
            try {
              // 使用 Octokit 获取默认分支
              const repoInfo = await octokit.repos.get({
                owner,
                repo
              });
              actualSourceBranch = repoInfo.data.default_branch;
              console.log(`   🔍 Found default branch: ${actualSourceBranch}`);
              
              // 清理失败的克隆尝试
              if (fs.existsSync(tempDir)) {
                fs.rmSync(tempDir, { recursive: true, force: true });
              }
              
              // 重新创建临时目录
              fs.mkdirSync(tempDir, { recursive: true });
              
              // 使用默认分支重新克隆
              await git.clone(repoUrl, tempDir, {
                '--single-branch': true,
                '--branch': actualSourceBranch
              });
            } catch (apiError) {
              console.error(`   ❌ Failed to get default branch: ${apiError.message}`);
              throw cloneError; // 重新抛出原始错误
            }
          } else {
            throw cloneError; // 重新抛出原始错误
          }
        } else {
          throw cloneError; // 其他错误，直接抛出
        }
      }

      const repoGit = simpleGit(tempDir);

      // 拉取最新代码
      await repoGit.pull('origin', actualSourceBranch);

      // 推送代码到目标仓库的目标分支
      const targetUrl = `https://x-access-token:${githubToken}@github.com/${targetRepo}.git`;
      await repoGit.push(targetUrl, `${actualSourceBranch}:${targetBranch}`, {
        '--force': true
      });

      console.log(`   ✅ Successfully synced ${repoName}: ${actualSourceBranch} -> ${targetBranch}`);

      // 清理当前仓库的临时目录
      if (fs.existsSync(tempDir)) {
        fs.rmSync(tempDir, { recursive: true, force: true });
      }
    }
    
    console.log('\n✅ All repositories synced successfully!');
    
  } catch (error) {
    console.error('❌ Sync failed:', error.message);
    console.error(error.stack);
    process.exit(1);
  } finally {
    // 清理主临时目录
    const mainTempDir = path.join(__dirname, 'temp');
    if (fs.existsSync(mainTempDir)) {
      fs.rmSync(mainTempDir, { recursive: true, force: true });
      console.log('Cleaned up main temp directory');
    }
  }
};

// 运行同步
syncRepositories();
