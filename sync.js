const simpleGit = require('simple-git');
const { Octokit } = require('@octokit/rest');
const fs = require('fs');
const path = require('path');

const CONFIG_FILE = path.join(__dirname, 'sync-config.json');
const TEMP_DIR = path.join(__dirname, 'temp');

const loadConfig = () => {
  if (!fs.existsSync(CONFIG_FILE)) {
    console.error('❌ 配置文件不存在: ' + CONFIG_FILE);
    process.exit(1);
  }

  try {
    const content = fs.readFileSync(CONFIG_FILE, 'utf8');
    const config = JSON.parse(content);
    
    if (!config.sourceRepos || !Array.isArray(config.sourceRepos) || config.sourceRepos.length === 0) {
      console.error('❌ 配置文件中 sourceRepos 数组为空或格式错误');
      process.exit(1);
    }
    
    return config;
  } catch (error) {
    console.error('❌ 读取配置文件失败: ' + error.message);
    process.exit(1);
  }
};

const getRepoInfo = (url) => {
  const match = url.match(/https:\/\/github\.com\/(.*?)\/(.*?)(?:\.git)?$/);
  if (!match) {
    throw new Error('无效的 GitHub 仓库 URL: ' + url);
  }
  return { owner: match[1], repo: match[2] };
};

const getDefaultBranch = async (octokit, owner, repo) => {
  try {
    const result = await octokit.repos.get({ owner, repo });
    return result.data.default_branch;
  } catch (error) {
    console.error('   ❌ 获取默认分支失败: ' + error.message);
    throw error;
  }
};

const cloneRepository = async (url, targetDir, branch) => {
  const git = simpleGit();
  
  try {
    await git.clone(url, targetDir, {
      '--single-branch': true,
      '--branch': branch
    });
    return branch;
  } catch (error) {
    if (error.message.includes('not found') || error.message.includes('does not exist')) {
      console.log(`   ⚠️  分支 ${branch} 不存在，尝试获取默认分支`);
      return null;
    }
    throw error;
  }
};

const removeWorkflows = async (repoGit) => {
  const workflowsDir = path.join(repoGit.cwd, '.github', 'workflows');
  if (fs.existsSync(workflowsDir)) {
    console.log('   🗑️  删除 .github/workflows 目录（避免权限问题）');
    fs.rmSync(workflowsDir, { recursive: true, force: true });
    
    try {
      await repoGit.rm('-r', '--cached', '.github/workflows');
      console.log('   🧹 从 Git 索引中移除工作流文件');
    } catch (error) {
      console.log('   ⚠️  清理 Git 索引时出错（可忽略）:', error.message);
    }
  }
};

const syncRepository = async (repoConfig, octokit, targetRepo, githubToken) => {
  const { repoUrl, sourceBranch, targetBranch, repoName } = repoConfig;
  const tempDir = path.join(TEMP_DIR, repoName);
  
  console.log(`\n🔄 同步仓库: ${repoName}`);
  console.log(`   源: ${repoUrl} (${sourceBranch})`);
  console.log(`   目标: ${targetRepo} (${targetBranch})`);

  let actualBranch = sourceBranch;

  try {
    actualBranch = await cloneRepository(repoUrl, tempDir, actualBranch);
    
    if (!actualBranch) {
      const { owner, repo } = getRepoInfo(repoUrl);
      actualBranch = await getDefaultBranch(octokit, owner, repo);
      console.log(`   🔍 找到默认分支: ${actualBranch}`);
      
      await cloneRepository(repoUrl, tempDir, actualBranch);
    }

    const repoGit = simpleGit(tempDir);
    await repoGit.pull('origin', actualBranch);
    
    await removeWorkflows(repoGit);

    const targetUrl = `https://x-access-token:${githubToken}@github.com/${targetRepo}.git`;
    await repoGit.push(targetUrl, `${actualBranch}:${targetBranch}`, {
      '--force': true
    });

    console.log(`   ✅ 同步成功: ${actualBranch} -> ${targetBranch}`);

  } catch (error) {
    console.error(`   ❌ 同步失败: ${error.message}`);
    throw error;
  } finally {
    if (fs.existsSync(tempDir)) {
      fs.rmSync(tempDir, { recursive: true, force: true });
    }
  }
};

const main = async () => {
  const config = loadConfig();
  const { sourceRepos, targetRepo } = config;
  const githubToken = process.env.GITHUB_TOKEN;

  if (!githubToken) {
    console.error('❌ 缺少 GITHUB_TOKEN 环境变量');
    process.exit(1);
  }

  if (!targetRepo) {
    console.error('❌ 配置文件中缺少 targetRepo 字段');
    process.exit(1);
  }

  const octokit = new Octokit({ auth: githubToken });

  console.log('🚀 开始同步仓库...');
  console.log(`📋 目标仓库: ${targetRepo}`);
  console.log(`📦 源仓库数量: ${sourceRepos.length}`);
  console.log('💡 提示: 已自动排除 .github/workflows 目录以避免权限问题');

  let successCount = 0;
  let failCount = 0;

  for (const repoConfig of sourceRepos) {
    try {
      await syncRepository(repoConfig, octokit, targetRepo, githubToken);
      successCount++;
    } catch (error) {
      failCount++;
      console.error(`\n❌ 仓库 ${repoConfig.repoName} 同步失败，继续处理下一个仓库`);
    }
  }

  console.log('\n📊 同步统计:');
  console.log(`   ✅ 成功: ${successCount}`);
  console.log(`   ❌ 失败: ${failCount}`);
  console.log(`   📦 总计: ${sourceRepos.length}`);

  if (failCount > 0) {
    console.log('\n⚠️  部分仓库同步失败');
    process.exit(1);
  } else {
    console.log('\n🎉 所有仓库同步成功！');
  }
};

main().catch(error => {
  console.error('\n❌ 程序异常:', error.message);
  console.error(error.stack);
  process.exit(1);
});