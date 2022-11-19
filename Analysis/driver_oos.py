from Energy.Analysis import oos_energy as oos
pd.set_option('display.max_columns', 150)
saveout=True
# %% get the data
oo = oos.OOSAnalysis()
# %% replicate results in paper
oo.gen_old_table('1_1')
oo.gen_old_table('2_2')
# %% check how rolling constant predicts actual outcomes
oo.check_const_for_actual()
# %% do predictions versus
oo.blended_oos('1_1','base',saveout)
oo.blended_oos('1_1','text',saveout)
oo.blended_oos('1_1','full',saveout)
oo.blended_oos('2_2','base',saveout) ## ***
oo.blended_oos('2_2','text',saveout) ## ***
oo.blended_oos('2_2','full',saveout)
