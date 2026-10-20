require "rails_helper"

RSpec.describe ImportGuard do
  it "初期行がない場合も安全に作成し、block失敗では初期行もrollbackする" do
    described_class.delete_all
    expect { described_class.synchronize { raise "rollback" } }.to raise_error("rollback")
    expect(described_class.count).to eq(0)
    described_class.synchronize { expect(described_class.count).to eq(1) }
  end

  it "初期化・lock取得に失敗した場合は書込みblockを実行しない" do
    executed = false
    allow(described_class).to receive(:create_or_find_by!).and_raise(ActiveRecord::ConnectionNotEstablished)
    expect { described_class.synchronize { executed = true } }.to raise_error(ActiveRecord::ConnectionNotEstablished)
    expect(executed).to be(false)
  end

  it "作成に成功してもlock失敗時はblockを実行しない" do
    executed = false
    allow_any_instance_of(described_class).to receive(:lock!).and_raise(ActiveRecord::LockWaitTimeout)
    expect { described_class.synchronize { executed = true } }.to raise_error(ActiveRecord::LockWaitTimeout)
    expect(executed).to be(false)
  end
end
